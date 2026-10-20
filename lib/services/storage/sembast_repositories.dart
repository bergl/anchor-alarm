import 'package:sembast/sembast.dart';

import '../../app/app_settings.dart';
import '../../domain/models.dart';
import 'repositories.dart';

/// Store names and keys of the app database.
abstract final class AppStores {
  /// Single record [settingsKey] holding [AppSettings] JSON.
  static final settings = stringMapStoreFactory.store('settings');
  static const settingsKey = 'app';

  /// Custom alarm profiles, key = profile id, value = profile JSON + [orderField].
  static final profiles = stringMapStoreFactory.store('profiles');
  static const orderField = '_order';

  /// Sessions, key = session id, value = [AnchorSession.toJson].
  static final sessions = stringMapStoreFactory.store('sessions');

  /// Track points, auto-increment int key, value = {sid, ...TrackPoint.toJson}.
  static final track = intMapStoreFactory.store('track');
  static const sessionIdField = 'sid';
}

Map<String, Object?> _mutable(Map<String, Object?> v) =>
    Map<String, Object?>.from(v);

class SembastSettingsRepository implements SettingsRepository {
  SembastSettingsRepository(this._db);

  final Database _db;

  RecordRef<String, Map<String, Object?>> get _record =>
      AppStores.settings.record(AppStores.settingsKey);

  @override
  Future<AppSettings> load() async {
    final v = await _record.get(_db);
    if (v == null) return const AppSettings();
    try {
      return AppSettings.fromJson(_mutable(v));
    } catch (_) {
      // Corrupt or incompatible settings: fall back to defaults rather than
      // preventing the app from starting.
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) =>
      _record.put(_db, settings.toJson());

  @override
  Future<List<AlarmProfile>> loadCustomProfiles() async {
    final records = await AppStores.profiles.find(
      _db,
      finder: Finder(sortOrders: [SortOrder(AppStores.orderField)]),
    );
    final result = <AlarmProfile>[];
    for (final r in records) {
      try {
        result.add(AlarmProfile.fromJson(_mutable(r.value)).copyWith(builtIn: false));
      } catch (_) {
        // Skip unreadable entries.
      }
    }
    return result;
  }

  @override
  Future<void> saveCustomProfiles(List<AlarmProfile> profiles) =>
      _db.transaction((txn) async {
        await AppStores.profiles.delete(txn);
        for (var i = 0; i < profiles.length; i++) {
          final p = profiles[i];
          await AppStores.profiles
              .record(p.id)
              .put(txn, {...p.toJson(), AppStores.orderField: i});
        }
      });
}

class SembastSessionRepository implements SessionRepository {
  SembastSessionRepository(this._db);

  final Database _db;

  static AnchorSession _session(RecordSnapshot<String, Map<String, Object?>> r) =>
      AnchorSession.fromJson(_mutable(r.value));

  Finder _trackFinder(String sessionId, {bool newestFirst = false, int? limit}) =>
      Finder(
        filter: Filter.equals(AppStores.sessionIdField, sessionId),
        sortOrders: [SortOrder('t', !newestFirst)],
        limit: limit,
      );

  @override
  Future<void> save(AnchorSession session) =>
      AppStores.sessions.record(session.id).put(_db, session.toJson());

  @override
  Future<AnchorSession?> get(String id) async {
    final v = await AppStores.sessions.record(id).get(_db);
    return v == null ? null : AnchorSession.fromJson(_mutable(v));
  }

  @override
  Future<AnchorSession?> loadActive() => _db.transaction((txn) async {
        final records = await AppStores.sessions.find(
          txn,
          finder: Finder(
            filter: Filter.isNull('endedAt'),
            sortOrders: [SortOrder('startedAt', false)],
          ),
        );
        if (records.isEmpty) return null;
        final active = _session(records.first);
        // Older dangling sessions (e.g. the app was killed and a new watch was
        // started without resuming): close them at their last known time.
        for (final r in records.skip(1)) {
          final s = _session(r);
          final last = await AppStores.track.findFirst(
            txn,
            finder: _trackFinder(s.id, newestFirst: true),
          );
          final endedAt = last == null
              ? s.startedAt
              : DateTime.fromMillisecondsSinceEpoch(last.value['t'] as int);
          await AppStores.sessions
              .record(s.id)
              .put(txn, s.copyWith(endedAt: endedAt).toJson());
        }
        return active;
      });

  @override
  Future<List<AnchorSession>> history() async {
    final records = await AppStores.sessions.find(
      _db,
      finder: Finder(
        filter: Filter.notNull('endedAt'),
        sortOrders: [SortOrder('startedAt', false)],
      ),
    );
    return records.map(_session).toList();
  }

  @override
  Future<void> delete(String id) => _db.transaction((txn) async {
        await AppStores.sessions.record(id).delete(txn);
        await AppStores.track.delete(
          txn,
          finder: Finder(filter: Filter.equals(AppStores.sessionIdField, id)),
        );
      });

  @override
  Future<void> appendTrack(String sessionId, List<TrackPoint> points) async {
    if (points.isEmpty) return;
    await AppStores.track.addAll(_db, [
      for (final p in points) {AppStores.sessionIdField: sessionId, ...p.toJson()},
    ]);
  }

  @override
  Future<List<TrackPoint>> track(String sessionId) async {
    final records = await AppStores.track.find(_db, finder: _trackFinder(sessionId));
    return [for (final r in records) TrackPoint.fromJson(_mutable(r.value))];
  }
}
