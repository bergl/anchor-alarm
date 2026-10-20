import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

import '../../app/app_settings.dart';

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
    this.wms,
  });

  /// Stable id, also the cache directory name.
  final String key;

  /// URL with `{z}`, `{x}`, `{y}` placeholders (order as the server wants it).
  /// For a WMS layer ([wms] set) this is the service base URL; use [url].
  final String urlTemplate;
  final String attribution;

  /// Highest zoom level the server provides; flutter_map scales beyond it.
  final int maxNativeZoom;

  /// Overlay with transparent background: a missing tile (HTTP 404) is a
  /// valid empty tile, not an error.
  final bool transparent;

  /// Set for a WMS layer: tiles are GetMap requests in EPSG:3857 whose BBOX
  /// is the Web Mercator tile z/x/y (the same tiles flutter_map's
  /// `WMSTileLayerOptions` requests), so they cache and download like XYZ.
  final WmsSource? wms;

  bool get isWms => wms != null;

  /// Tile URL for z/x/y (XYZ template, or a WMS GetMap request).
  String url(int z, int x, int y) {
    final w = wms;
    if (w != null) return w.getMapUrl(z, x, y);
    return urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
  }

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

  /// EMODnet Bathymetry "World Base Layer" (WMTS, tile matrix set
  /// `web_mercator` = EPSG:3857, levels 0-15): shaded sea-floor and land
  /// relief, global. The WMTS ResourceURL is
  /// `.../{TileMatrixSet}/{TileMatrix}/{TileCol}/{TileRow}.png`, i.e. z/x/y.
  static const emodnetBase = TileLayerSpec(
    key: 'emodnet_base',
    urlTemplate:
        'https://tiles.emodnet-bathymetry.eu/2020/baselayer/web_mercator/{z}/{x}/{y}.png',
    attribution: 'EMODnet Bathymetry Consortium',
    maxNativeZoom: 15,
  );

  /// EMODnet mean depth, multicolour ramp (WMS `emodnet:mean_multicolour`).
  /// European seas only, ~115 m grid; transparent over land / outside.
  static const emodnetDepth = TileLayerSpec(
    key: 'emodnet_depth',
    urlTemplate: emodnetWmsUrl,
    attribution: 'EMODnet Bathymetry Consortium',
    maxNativeZoom: 14,
    transparent: true,
    wms: WmsSource(baseUrl: '$emodnetWmsUrl?', layers: ['emodnet:mean_multicolour']),
  );

  /// GEBCO grid colour-shaded for elevation (WMS `GEBCO_LATEST_2`), global,
  /// 15 arc-second (~460 m) grid.
  static const gebcoDepth = TileLayerSpec(
    key: 'gebco_depth',
    urlTemplate: gebcoWmsUrl,
    attribution: 'GEBCO Compilation Group, GEBCO Grid',
    maxNativeZoom: 12,
    transparent: true,
    wms: WmsSource(baseUrl: '$gebcoWmsUrl?', layers: ['GEBCO_LATEST_2']),
  );

  static const all = [osm, openSeaMap, esriSatellite, emodnetBase, emodnetDepth, gebcoDepth];

  static const emodnetWmsUrl = 'https://ows.emodnet-bathymetry.eu/wms';
  static const gebcoWmsUrl = 'https://wms.gebco.net/mapserv';
}

/// Base map spec for [b] (null for [BaseMap.none]).
TileLayerSpec? baseMapSpec(BaseMap b) => switch (b) {
      BaseMap.osm => TileLayerSpec.osm,
      BaseMap.satellite => TileLayerSpec.esriSatellite,
      BaseMap.bathymetry => TileLayerSpec.emodnetBase,
      BaseMap.none => null,
    };

/// Depth overlay spec for [d] (null for [DepthLayer.none]).
TileLayerSpec? depthLayerSpec(DepthLayer d) => switch (d) {
      DepthLayer.emodnet => TileLayerSpec.emodnetDepth,
      DepthLayer.gebco => TileLayerSpec.gebcoDepth,
      DepthLayer.none => null,
    };

/// The tile layers shown for [s], bottom to top: base map, depth overlay,
/// seamarks. WMS overlays are included; [TileLayerSpec.url] gives their tile
/// URLs, so they can be downloaded for offline use like any XYZ layer.
List<TileLayerSpec> activeTileLayers(AppSettings s) => [
      ?baseMapSpec(s.baseMap),
      ?depthLayerSpec(s.depthLayer),
      if (s.seamarks) TileLayerSpec.openSeaMap,
    ];

/// A WMS 1.1.1 GetMap source in EPSG:3857 with 256 px tiles.
class WmsSource {
  const WmsSource({
    required this.baseUrl,
    required this.layers,
    this.styles = const [],
    this.format = 'image/png',
    this.version = '1.1.1',
  });

  /// Service URL ending in `?` (parameters are appended with `&`).
  final String baseUrl;
  final List<String> layers;
  final List<String> styles;
  final String format;
  final String version;

  static const _r = 20037508.342789244;

  /// GetMap URL for Web Mercator tile z/x/y. Mirrors the parameter order of
  /// flutter_map's `WMSTileLayerOptions.getUrl`.
  String getMapUrl(int z, int x, int y, {int size = 256}) {
    final span = 2 * _r / (1 << z);
    final minX = -_r + x * span;
    final maxX = minX + span;
    final maxY = _r - y * span;
    final minY = maxY - span;
    return '$baseUrl&service=WMS&request=GetMap'
        '&layers=${layers.map(Uri.encodeComponent).join(',')}'
        '&styles=${styles.map(Uri.encodeComponent).join(',')}'
        '&format=${Uri.encodeComponent(format)}'
        '&srs=${Uri.encodeComponent('EPSG:3857')}'
        '&version=${Uri.encodeComponent(version)}'
        '&transparent=true&width=$size&height=$size'
        '&bbox=$minX,$minY,$maxX,$maxY';
  }
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
