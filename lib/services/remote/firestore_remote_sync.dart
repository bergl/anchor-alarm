import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models.dart';
import '../../domain/watch_engine.dart';
import 'remote_models.dart';
import 'remote_store.dart';
import 'remote_sync.dart';

/// Publishes the anchor watch to `watches/{watchId}` for remote monitoring.
///
/// * **Opt-in per watch**: nothing is uploaded until [startSharing] is called
///   for the session ("Share this watch"). The share record is kept on the
///   device by session id, so a watch restored after an app restart keeps
///   publishing to the same document.
/// * **Throttled**: the watch controller calls [publish] about every 5 s and
///   on events; this writes only when something material changed (see
///   [isMaterialChange]) and otherwise sends a heartbeat every [heartbeat].
/// * **Never blocks or throws into the watch loop**: writes are not awaited
///   (Firestore queues them while offline), errors are logged.
class FirestoreRemoteSync implements RemoteSync {
  FirestoreRemoteSync({
    required this.store,
    required this.local,
    this.heartbeat = const Duration(seconds: 60),
    int Function()? tzOffsetMin,
  }) : _tzOffsetMin = tzOffsetMin ?? (() => DateTime.now().timeZoneOffset.inMinutes);

  final RemoteWatchStore store;
  final RemoteLocalStore local;
  final Duration heartbeat;
  final int Function() _tzOffsetMin;

  static const _signInRetry = Duration(seconds: 30);

  final _changes = StreamController<ShareRecord>.broadcast();
  final _last = <String, (RemoteWatchWrite, DateTime)>{};
  String? _uid;
  Future<String?>? _signingIn;
  DateTime? _signInRetryAt;

  /// Number of writes sent (for diagnostics and tests).
  int writes = 0;

  /// Last write error, if any (shown in the share sheet).
  Object? lastError;

  /// Share records as they change (start / stop sharing, end of watch).
  Stream<ShareRecord> get changes => _changes.stream;

  ShareRecord? recordFor(String sessionId) => local.shareFor(sessionId);

  String get boatName => local.boatName;

  Future<void> setBoatName(String name) async {
    await local.saveBoatName(name.trim());
  }

  /// Turns sharing on for [session] and writes the watch document. Throws
  /// [RemoteException] when this device cannot sign in (offline on the very
  /// first use).
  Future<ShareRecord> startSharing(AnchorSession session, WatchSnapshot? snapshot) async {
    final uid = await _ensureUid(force: true);
    if (uid == null) {
      throw const RemoteException(RemoteErrorKind.offline, 'Could not sign in.');
    }
    final existing = local.shareFor(session.id);
    final rec = existing != null && existing.active
        ? existing
        : ShareRecord(
            sessionId: session.id,
            watchId: newWatchId(),
            shareKey: newShareKey(),
            active: true,
          );
    await local.saveShare(rec);
    _last.remove(session.id);
    _changes.add(rec);
    _send(rec, RemoteWatchWrite.from(
      ownerUid: uid,
      shareKey: rec.shareKey,
      boatName: local.boatName,
      session: session,
      snapshot: snapshot,
      tzOffsetMin: _tzOffsetMin(),
    ));
    return rec;
  }

  /// "Stop sharing": rotates the share key (every existing link stops
  /// working), ends the remote watch, removes the watchers and stops
  /// uploading. Sharing again creates a new link.
  Future<void> stopSharing(String sessionId) async {
    final rec = local.shareFor(sessionId);
    if (rec == null || !rec.active) return;
    final stopped = rec.copyWith(active: false, shareKey: newShareKey());
    await local.saveShare(stopped);
    _last.remove(sessionId);
    _changes.add(stopped);
    _guard(store.stopSharing(rec.watchId,
        newShareKey: stopped.shareKey, endedAt: clock.now()));
  }

  @override
  Future<void> publish(AnchorSession session, WatchSnapshot snapshot) async {
    final rec = local.shareFor(session.id);
    if (rec == null || !rec.active) return;
    final uid = await _ensureUid();
    if (uid == null) return;
    final w = RemoteWatchWrite.from(
      ownerUid: uid,
      shareKey: rec.shareKey,
      boatName: local.boatName,
      session: session,
      snapshot: snapshot,
      tzOffsetMin: _tzOffsetMin(),
    );
    final last = _last[session.id];
    if (last != null &&
        !isMaterialChange(last.$1, w) &&
        clock.now().difference(last.$2) < heartbeat) {
      return;
    }
    _send(rec, w);
  }

  @override
  Future<void> end(AnchorSession session) async {
    final rec = local.shareFor(session.id);
    if (rec == null || !rec.active) return;
    final ended = session.endedAt ?? clock.now();
    final last = _last[session.id]?.$1;
    final uid = _uid;
    if (uid != null) {
      final w = last?.copyWith(endedAt: ended, ringing: false, state: WatchState.inactive) ??
          RemoteWatchWrite.from(
            ownerUid: uid,
            shareKey: rec.shareKey,
            boatName: local.boatName,
            session: session.copyWith(endedAt: ended),
            tzOffsetMin: _tzOffsetMin(),
          );
      _send(rec, w);
    }
    final done = rec.copyWith(active: false);
    await local.saveShare(done);
    _last.remove(session.id);
    _changes.add(done);
  }

  void _send(ShareRecord rec, RemoteWatchWrite w) {
    _last[rec.sessionId] = (w, clock.now());
    writes++;
    _guard(store.putWatch(rec.watchId, w));
  }

  void _guard(Future<void> f) {
    unawaited(f.then((_) => lastError = null, onError: (Object e) {
      lastError = e;
      debugPrint('Remote sync write failed: $e');
    }));
  }

  Future<String?> _ensureUid({bool force = false}) {
    final uid = _uid;
    if (uid != null) return Future.value(uid);
    final retryAt = _signInRetryAt;
    if (!force && retryAt != null && clock.now().isBefore(retryAt)) return Future.value();
    return _signingIn ??= () async {
      try {
        final u = await store.signIn().timeout(const Duration(seconds: 20));
        _uid = u;
        return u;
      } catch (e) {
        debugPrint('Remote sign-in failed: $e');
        _signInRetryAt = clock.now().add(_signInRetry);
        return null;
      } finally {
        _signingIn = null;
      }
    }();
  }
}
