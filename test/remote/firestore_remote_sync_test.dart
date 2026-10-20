import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/watch_engine.dart';
import 'package:anchor_alarm/services/remote/firestore_remote_sync.dart';
import 'package:anchor_alarm/services/remote/remote_models.dart';
import 'package:anchor_alarm/services/remote/remote_store.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'remote_fakes.dart';

const anchor = LatLng(43.5, 16.4);
final t0 = DateTime.utc(2026, 10, 20, 12);

final sess = AnchorSession(
  id: 's1',
  anchor: anchor,
  radiusM: 50,
  initialRadiusM: 50,
  profile: AlarmProfile.builtIns[1],
  startedAt: t0,
);

WatchSnapshot snap({double distance = 30, WatchState state = WatchState.safe, bool ringing = false}) =>
    WatchSnapshot(
      time: t0,
      state: state,
      reasons: state == WatchState.alarm ? {AlertReason.drag} : const {},
      ringing: ringing,
      radiusM: 50,
      warningRadiusM: 45,
      maxDistanceM: distance,
      distanceM: distance,
      position: destination(anchor, 90, distance),
      accuracyM: 5,
    );

void main() {
  late FakeRemoteStore store;
  late MemoryRemoteLocalStore local;
  late FirestoreRemoteSync sync;

  setUp(() {
    store = FakeRemoteStore();
    local = MemoryRemoteLocalStore(boatName: 'Kestrel');
    sync = FirestoreRemoteSync(store: store, local: local, tzOffsetMin: () => 60);
  });

  test('uploads nothing unless sharing is switched on', () async {
    await sync.publish(sess, snap());
    await sync.end(sess.copyWith(endedAt: t0));
    expect(store.puts, isEmpty);
    expect(store.signIns, 0);
  });

  test('start sharing writes the watch with a new id and key', () async {
    final rec = await sync.startSharing(sess, snap());
    expect(rec.active, isTrue);
    expect(rec.watchId, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
    expect(rec.shareKey, matches(RegExp(r'^[A-Z2-7]{26}$')));
    await pumpEventQueue();
    expect(store.puts, hasLength(1));
    final (id, w) = store.puts.single;
    expect(id, rec.watchId);
    expect(w.ownerUid, 'owner-uid');
    expect(w.shareKey, rec.shareKey);
    expect(w.boatName, 'Kestrel');
    expect(w.tzOffsetMin, 60);
    expect(local.shareFor('s1'), isNotNull);
  });

  test('throttles: no write without material change, heartbeat every 60 s', () {
    fakeAsync((fa) {
      sync.startSharing(sess, snap());
      fa.flushMicrotasks();
      expect(store.puts, hasLength(1));

      // The controller publishes every ~5 s; GPS jitter is not material.
      for (var i = 1; i <= 11; i++) {
        fa.elapse(const Duration(seconds: 5));
        sync.publish(sess, snap(distance: 30 + (i.isEven ? 0.5 : -0.5)));
        fa.flushMicrotasks();
      }
      expect(store.puts, hasLength(1), reason: '55 s of jitter: no writes');

      fa.elapse(const Duration(seconds: 5));
      sync.publish(sess, snap(distance: 30.5));
      fa.flushMicrotasks();
      expect(store.puts, hasLength(2), reason: 'heartbeat after 60 s');

      fa.elapse(const Duration(seconds: 5));
      sync.publish(sess, snap(distance: 30));
      fa.flushMicrotasks();
      expect(store.puts, hasLength(2));
    });
  });

  test('material changes are written immediately', () {
    fakeAsync((fa) {
      sync.startSharing(sess, snap());
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 5));
      sync.publish(sess, snap(distance: 36));
      fa.flushMicrotasks();
      expect(store.puts, hasLength(2), reason: 'moved 6 m');
      fa.elapse(const Duration(seconds: 1));
      sync.publish(sess, snap(distance: 36, state: WatchState.alarm, ringing: true));
      fa.flushMicrotasks();
      expect(store.puts, hasLength(3));
      expect(store.puts.last.$2.ringing, isTrue);
      expect(store.puts.last.$2.reasons, {AlertReason.drag});
    });
  });

  test('end writes the ended, silent watch and stops uploading', () async {
    await sync.startSharing(sess, snap(state: WatchState.alarm, ringing: true));
    await sync.end(sess.copyWith(endedAt: t0.add(const Duration(hours: 1))));
    await pumpEventQueue();
    final last = store.puts.last.$2;
    expect(last.endedAt, t0.add(const Duration(hours: 1)));
    expect(last.ringing, isFalse);
    expect(last.state, WatchState.inactive);
    expect(local.shareFor('s1')!.active, isFalse);
    final n = store.puts.length;
    await sync.publish(sess, snap());
    expect(store.puts, hasLength(n));
  });

  test('stop sharing rotates the key, ends remotely and stops uploading', () async {
    final rec = await sync.startSharing(sess, snap());
    await sync.stopSharing('s1');
    await pumpEventQueue();
    expect(store.stops, hasLength(1));
    expect(store.stops.single.$1, rec.watchId);
    expect(store.stops.single.$2, isNot(rec.shareKey));
    expect(local.shareFor('s1')!.active, isFalse);
    final n = store.puts.length;
    await sync.publish(sess, snap(distance: 40));
    expect(store.puts, hasLength(n));

    // Sharing again: a new link.
    final again = await sync.startSharing(sess, snap());
    expect(again.watchId, isNot(rec.watchId));
  });

  test('a restored watch keeps publishing to the same document', () async {
    final rec = await sync.startSharing(sess, snap());
    // App restart: new sync instance, same device store.
    final restored = FirestoreRemoteSync(store: store, local: local);
    await restored.publish(sess, snap(distance: 33));
    await pumpEventQueue();
    expect(store.puts.last.$1, rec.watchId);
    expect(store.puts.last.$2.shareKey, rec.shareKey);
  });

  test('never throws into the watch loop: sign-in and write failures', () async {
    await sync.startSharing(sess, snap());
    store.putError = const RemoteException(RemoteErrorKind.offline);
    await sync.publish(sess, snap(distance: 45));
    await pumpEventQueue();
    expect(sync.lastError, isA<RemoteException>());

    // Fresh device that cannot sign in: publish is a silent no-op, retried later.
    final offlineStore = FakeRemoteStore()..signInFails = true;
    final local2 = MemoryRemoteLocalStore();
    await local2.saveShare(const ShareRecord(
        sessionId: 's1', watchId: 'AbCdEfGhIj0123456789', shareKey: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', active: true));
    final s2 = FirestoreRemoteSync(store: offlineStore, local: local2);
    await s2.publish(sess, snap());
    await s2.publish(sess, snap());
    expect(offlineStore.puts, isEmpty);
    expect(offlineStore.signIns, 1, reason: 'retry waits 30 s');
    await expectLater(s2.startSharing(sess, snap()), throwsA(isA<RemoteException>()));
  });
}
