import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import 'remote_models.dart';
import 'remote_store.dart';

/// [RemoteLocalStore] in the app's sembast database (store `remote`), loaded
/// into memory once so reads are synchronous.
class SembastRemoteLocalStore implements RemoteLocalStore {
  SembastRemoteLocalStore._(this._db, this._shares, this._boatName, this._monitored);

  static final _store = StoreRef<String, Object?>('remote');
  static const _sharesKey = 'shares';
  static const _boatNameKey = 'boatName';
  static const _monitoredKey = 'monitored';

  final Database _db;
  final Map<String, ShareRecord> _shares;
  String _boatName;
  List<MonitoredBoat> _monitored;

  static Future<SembastRemoteLocalStore> open(Database db) async {
    final shares = <String, ShareRecord>{};
    var boatName = '';
    var monitored = <MonitoredBoat>[];
    try {
      final s = await _store.record(_sharesKey).get(db);
      if (s is Map) {
        for (final v in s.values) {
          final r = ShareRecord.fromJson(Map<String, Object?>.from(v as Map));
          shares[r.sessionId] = r;
        }
      }
      final n = await _store.record(_boatNameKey).get(db);
      if (n is String) boatName = n;
      final m = await _store.record(_monitoredKey).get(db);
      if (m is List) {
        monitored = [
          for (final b in m) MonitoredBoat.fromJson(Map<String, Object?>.from(b as Map)),
        ];
      }
    } catch (e) {
      debugPrint('Remote local store unreadable, starting empty: $e');
    }
    return SembastRemoteLocalStore._(db, shares, boatName, monitored);
  }

  @override
  ShareRecord? shareFor(String sessionId) => _shares[sessionId];

  @override
  Future<void> saveShare(ShareRecord record) async {
    _shares[record.sessionId] = record;
    // Keep the active record and a few recent ones; old sessions don't need theirs.
    if (_shares.length > 20) {
      _shares.removeWhere((id, r) => !r.active && id != record.sessionId);
    }
    await _store
        .record(_sharesKey)
        .put(_db, {for (final r in _shares.values) r.sessionId: r.toJson()});
  }

  @override
  String get boatName => _boatName;

  @override
  Future<void> saveBoatName(String name) async {
    _boatName = name;
    await _store.record(_boatNameKey).put(_db, name);
  }

  @override
  List<MonitoredBoat> get monitored => List.unmodifiable(_monitored);

  @override
  Future<void> saveMonitored(List<MonitoredBoat> boats) async {
    _monitored = List.of(boats);
    await _store.record(_monitoredKey).put(_db, [for (final b in boats) b.toJson()]);
  }
}
