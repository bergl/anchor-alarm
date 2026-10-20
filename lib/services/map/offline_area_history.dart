import 'package:latlong2/latlong.dart';

export 'offline_area_history_io.dart'
    if (dart.library.js_interop) 'offline_area_history_web.dart';

/// An area completed by the automatic offline download.
class OfflineAreaRecord {
  const OfflineAreaRecord({
    required this.centre,
    required this.completedAt,
    required this.layerKeys,
  });

  final LatLng centre;
  final DateTime completedAt;

  /// [TileLayerSpec.key]s that were downloaded.
  final List<String> layerKeys;

  Map<String, Object?> toJson() => {
        'lat': centre.latitude,
        'lon': centre.longitude,
        'at': completedAt.toUtc().toIso8601String(),
        'layers': layerKeys,
      };

  static OfflineAreaRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lon = j['lon'], at = j['at'], layers = j['layers'];
    if (lat is! num || lon is! num || at is! String || layers is! List) return null;
    final t = DateTime.tryParse(at);
    if (t == null) return null;
    return OfflineAreaRecord(
      centre: LatLng(lat.toDouble(), lon.toDouble()),
      completedAt: t,
      layerKeys: layers.whereType<String>().toList(),
    );
  }
}

/// The last few areas downloaded automatically, so the same anchorage is not
/// downloaded again on every watch.
abstract class OfflineAreaHistory {
  Future<List<OfflineAreaRecord>> load();
  Future<void> save(List<OfflineAreaRecord> records);
}

/// Keeps the history in memory only (tests, web).
class MemoryOfflineAreaHistory implements OfflineAreaHistory {
  MemoryOfflineAreaHistory([List<OfflineAreaRecord>? records])
      : records = records ?? [];
  List<OfflineAreaRecord> records;

  @override
  Future<List<OfflineAreaRecord>> load() async => List.of(records);

  @override
  Future<void> save(List<OfflineAreaRecord> r) async => records = List.of(r);
}
