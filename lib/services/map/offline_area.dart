import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

import 'tile_layer_spec.dart';

/// A ring of detail around the centre: zoom [minZoom]–[maxZoom] for a square
/// of "radius" [radiusM] (half the side length).
class OfflineBand {
  const OfflineBand({
    required this.name,
    required this.radiusM,
    required this.minZoom,
    required this.maxZoom,
    required this.minRadiusM,
  });

  final String name;
  final double radiusM;
  final int minZoom;
  final int maxZoom;

  /// The planner never shrinks the band below this radius (it drops zoom
  /// levels or the whole band instead).
  final double minRadiusM;

  OfflineBand copyWith({double? radiusM, int? maxZoom}) => OfflineBand(
        name: name,
        radiusM: radiusM ?? this.radiusM,
        minZoom: minZoom,
        maxZoom: maxZoom ?? this.maxZoom,
        minRadiusM: minRadiusM,
      );

  @override
  String toString() =>
      '$name z$minZoom–$maxZoom ±${radiusM.round()} m';
}

/// One `TileDownloader.downloadArea` call of a plan.
class OfflineAreaRequest {
  const OfflineAreaRequest({
    required this.band,
    required this.bounds,
    required this.layers,
    required this.tiles,
  });

  final OfflineBand band;
  final LatLngBounds bounds;
  final List<TileLayerSpec> layers;

  /// Tiles of all [layers] in this request (before skipping fresh ones).
  final int tiles;

  int get minZoom => band.minZoom;
  int get maxZoom => band.maxZoom;
}

/// What to download around a position for offline use.
class OfflineAreaPlan {
  const OfflineAreaPlan({
    required this.centre,
    required this.layers,
    required this.requests,
  });

  final LatLng centre;
  final List<TileLayerSpec> layers;
  final List<OfflineAreaRequest> requests;

  int get totalTiles => requests.fold(0, (a, r) => a + r.tiles);
  bool get isEmpty => totalTiles == 0;

  /// Rough download size (see [estimatedTileBytes]).
  int get estimatedBytes {
    var total = 0;
    for (final r in requests) {
      for (final l in r.layers) {
        final top = math.min(r.maxZoom, l.maxNativeZoom);
        if (top < r.minZoom) continue;
        total += countTilesInArea(
                bounds: r.bounds, minZoom: r.minZoom, maxZoom: top, layers: [l]) *
            estimatedTileBytes(l);
      }
    }
    return total;
  }

  @override
  String toString() => 'OfflineAreaPlan($totalTiles tiles: ${requests.map((r) => '${r.band}=${r.tiles}').join(', ')})';
}

/// Typical size of one tile: opaque base maps ~20 kB, transparent overlays
/// (seamarks, mostly empty) much less.
int estimatedTileBytes(TileLayerSpec layer) => layer.transparent ? 4 * 1024 : 20 * 1024;

/// Plans the automatic "chart around the anchor" download.
///
/// Three bands by default (≈250 tiles per layer at mid latitudes):
/// overview z10–12 within 15 km, approach z13–15 within 3 km and the
/// anchorage z16–17 within 600 m. When the total for all layers exceeds
/// [maxTiles], the outer bands are shrunk first, then dropped, and finally
/// the innermost band loses its highest zoom levels — a plan never exceeds
/// [maxTiles]. Volumes stay deliberately modest (OSM tile usage policy).
class OfflineAreaPlanner {
  const OfflineAreaPlanner({
    this.bands = defaultBands,
    this.maxTiles = maxDownloadTiles,
  });

  /// Outermost first.
  final List<OfflineBand> bands;
  final int maxTiles;

  static const defaultBands = [
    OfflineBand(name: 'overview', radiusM: 15000, minZoom: 10, maxZoom: 12, minRadiusM: 5000),
    OfflineBand(name: 'approach', radiusM: 3000, minZoom: 13, maxZoom: 15, minRadiusM: 1000),
    OfflineBand(name: 'anchorage', radiusM: 600, minZoom: 16, maxZoom: 17, minRadiusM: 250),
  ];

  /// Shrink step for an over-budget band radius.
  static const _shrink = 0.8;

  OfflineAreaPlan plan(LatLng centre, List<TileLayerSpec> layers) {
    if (layers.isEmpty) {
      return OfflineAreaPlan(centre: centre, layers: layers, requests: const []);
    }
    var current = List<OfflineBand>.of(bands);

    List<OfflineAreaRequest> build() => [
          for (final b in current)
            if (b.maxZoom >= b.minZoom)
              _request(centre, b, layers),
        ];

    var requests = build();
    int total() => requests.fold(0, (a, r) => a + r.tiles);

    // 1. Shrink outer bands first, down to their minimum radius.
    for (var i = 0; i < current.length && total() > maxTiles; i++) {
      while (total() > maxTiles && current[i].radiusM > current[i].minRadiusM) {
        final r = math.max(current[i].minRadiusM, current[i].radiusM * _shrink);
        current[i] = current[i].copyWith(radiusM: r);
        requests = build();
      }
    }
    // 2. Drop outer bands entirely, keeping the innermost.
    while (total() > maxTiles && current.length > 1) {
      current.removeAt(0);
      requests = build();
    }
    // 3. Lower the detail of the remaining band.
    while (total() > maxTiles && current.isNotEmpty) {
      final b = current.single;
      if (b.maxZoom <= b.minZoom) {
        current = [];
      } else {
        current = [b.copyWith(maxZoom: b.maxZoom - 1)];
      }
      requests = build();
    }
    return OfflineAreaPlan(centre: centre, layers: layers, requests: requests);
  }

  OfflineAreaRequest _request(LatLng c, OfflineBand b, List<TileLayerSpec> layers) {
    final bounds = boundsAround(c, b.radiusM);
    // Layers without tiles at these zooms (low max native zoom) are left out;
    // the map scales their deepest tiles from an outer band.
    final ls = [for (final l in layers) if (l.maxNativeZoom >= b.minZoom) l];
    return OfflineAreaRequest(
      band: b,
      bounds: bounds,
      layers: ls,
      tiles: countTilesInArea(
          bounds: bounds, minZoom: b.minZoom, maxZoom: b.maxZoom, layers: ls),
    );
  }
}

/// Square bounds of half side [radiusM] around [c].
LatLngBounds boundsAround(LatLng c, double radiusM) {
  const mPerDegLat = 111320.0;
  final dLat = radiusM / mPerDegLat;
  final cosLat = math.cos(c.latitude * math.pi / 180).abs();
  final dLon = math.min(179.0, radiusM / (mPerDegLat * math.max(cosLat, 0.01)));
  return LatLngBounds(
    LatLng((c.latitude - dLat).clamp(-85.0, 85.0), (c.longitude - dLon).clamp(-180.0, 180.0)),
    LatLng((c.latitude + dLat).clamp(-85.0, 85.0), (c.longitude + dLon).clamp(-180.0, 180.0)),
  );
}
