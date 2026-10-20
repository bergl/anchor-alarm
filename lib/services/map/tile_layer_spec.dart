import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

/// User-Agent sent with every tile request. The OSM tile usage policy
/// (https://operations.osmfoundation.org/policies/tiles/) requires a valid,
/// identifying User-Agent. (Browsers do not allow overriding it on the web.)
const tileUserAgent = 'AnchorAlarm/0.1 (+https://github.com/bergl/anchor-alarm)';

/// A raster tile source.
class TileLayerSpec {
  const TileLayerSpec({
    required this.key,
    required this.urlTemplate,
    required this.attribution,
    this.maxNativeZoom = 19,
    this.transparent = false,
  });

  /// Stable id, also the cache directory name.
  final String key;

  /// URL with `{z}`, `{x}`, `{y}` placeholders (order as the server wants it).
  final String urlTemplate;
  final String attribution;

  /// Highest zoom level the server provides; flutter_map scales beyond it.
  final int maxNativeZoom;

  /// Overlay with transparent background: a missing tile (HTTP 404) is a
  /// valid empty tile, not an error.
  final bool transparent;

  String url(int z, int x, int y) => urlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  static const osm = TileLayerSpec(
    key: 'osm',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    maxNativeZoom: 19,
  );

  static const openSeaMap = TileLayerSpec(
    key: 'seamarks',
    urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
    attribution: '© OpenSeaMap contributors',
    maxNativeZoom: 18,
    transparent: true,
  );

  /// Esri World Imagery. Note the `{y}/{x}` order in the URL.
  static const esriSatellite = TileLayerSpec(
    key: 'esri_imagery',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: 'Esri, Maxar, Earthstar Geographics',
    maxNativeZoom: 19,
  );

  static const all = [osm, openSeaMap, esriSatellite];
}

/// Upper limit for one "download this area" request. Bulk downloading from
/// tile.openstreetmap.org is discouraged by the OSM tile usage policy (the
/// servers are donated and run by volunteers), so the downloader must stay
/// modest: a small anchorage at harbour zoom levels, not whole coastlines.
const maxDownloadTiles = 3000;

/// Max parallel requests while downloading (OSM policy: at most 2).
const maxDownloadParallel = 2;

/// Thrown when an area download would exceed [maxDownloadTiles].
class TileDownloadLimitException implements Exception {
  const TileDownloadLimitException(this.requested, this.limit);
  final int requested;
  final int limit;
  @override
  String toString() =>
      'Area too large: $requested tiles (limit $limit). Zoom in or lower the max zoom.';
}

/// Cooperative cancellation for [TileDownloader.downloadArea].
class TileDownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// A tile address.
typedef TileXYZ = ({int z, int x, int y});

const _maxLat = 85.05112878;

int _lonToX(double lon, int n) =>
    ((lon + 180) / 360 * n).floor().clamp(0, n - 1);

int _latToY(double lat, int n) {
  final r = lat.clamp(-_maxLat, _maxLat) * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  return y.floor().clamp(0, n - 1);
}

/// Tile x/y ranges covering [bounds] at zoom [z].
({int minX, int maxX, int minY, int maxY}) tileRange(LatLngBounds bounds, int z) {
  final n = 1 << z;
  return (
    minX: _lonToX(bounds.west, n),
    maxX: _lonToX(bounds.east, n),
    minY: _latToY(bounds.north, n),
    maxY: _latToY(bounds.south, n),
  );
}

/// All tiles covering [bounds] from [minZoom] to [maxZoom] (inclusive).
Iterable<TileXYZ> tilesInBounds(LatLngBounds bounds, int minZoom, int maxZoom) sync* {
  for (var z = minZoom; z <= maxZoom; z++) {
    final r = tileRange(bounds, z);
    for (var x = r.minX; x <= r.maxX; x++) {
      for (var y = r.minY; y <= r.maxY; y++) {
        yield (z: z, x: x, y: y);
      }
    }
  }
}

/// Number of tiles needed to cover [bounds] for all [layers], each limited to
/// its [TileLayerSpec.maxNativeZoom].
int countTilesInArea({
  required LatLngBounds bounds,
  required int minZoom,
  required int maxZoom,
  required List<TileLayerSpec> layers,
}) {
  var total = 0;
  for (final layer in layers) {
    final top = math.min(maxZoom, layer.maxNativeZoom);
    for (var z = minZoom; z <= top; z++) {
      final r = tileRange(bounds, z);
      total += (r.maxX - r.minX + 1) * (r.maxY - r.minY + 1);
    }
  }
  return total;
}
