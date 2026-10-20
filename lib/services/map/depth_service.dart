import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A charted depth at a point.
class DepthSample {
  const DepthSample({
    required this.depthM,
    required this.source,
    required this.resolution,
  });

  /// Depth below the chart datum / mean sea level in metres, positive down.
  final double depthM;

  /// Short source name for captions, e.g. "EMODnet".
  final String source;

  /// Grid resolution note, e.g. "~115 m grid".
  final String resolution;

  @override
  String toString() => 'DepthSample($depthM m, $source, $resolution)';
}

/// Looks up the charted (gridded) depth at a position.
///
/// 1. EMODnet Bathymetry WMS GetFeatureInfo on `emodnet:mean`
///    (European seas, 1/16 arc-minute ≈ 115 m grid; JSON, property `Depth`
///    is an *elevation*: negative = below sea level, positive = land,
///    exactly 0 = no data).
/// 2. Fallback: GEBCO WMS GetFeatureInfo on `GEBCO_LATEST_2`
///    (global, 15 arc-second ≈ 460 m grid; text/plain `value_list` is
///    an elevation as well).
///
/// Returns null on land, without data, offline, on server errors and after
/// [timeout]. Never throws. Both servers send `Access-Control-Allow-Origin: *`
/// so this also works on the web.
class DepthService {
  DepthService({http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Per-request timeout.
  final Duration timeout;

  static const emodnetSource = 'EMODnet';
  static const gebcoSource = 'GEBCO';

  /// EMODnet DTM cell size: 1/16 arc-minute.
  static const _emodnetCellDeg = 1 / 960;

  /// GEBCO grid cell size: 15 arc-seconds.
  static const _gebcoCellDeg = 1 / 240;

  Future<DepthSample?> depthAt(LatLng p) async {
    // Elevations, positive up.
    final e = await _guard(() => _get(emodnetUrl(p), parseEmodnet));
    if (e != null) {
      // Land per the finer EMODnet grid: GEBCO (coarser) is not better.
      if (e >= 0) return null;
      return DepthSample(depthM: -e, source: emodnetSource, resolution: '~115 m grid');
    }
    final g = await _guard(() => _get(gebcoUrl(p), parseGebco));
    if (g == null || g >= 0) return null;
    return DepthSample(depthM: -g, source: gebcoSource, resolution: '~460 m grid');
  }

  Future<double?> _guard(Future<double?> Function() f) async {
    try {
      return await f().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// GetFeatureInfo URL for a 3×3 pixel map centred on [p], one pixel being
  /// [cellDeg] wide, querying the centre pixel.
  static Uri featureInfoUrl({
    required String baseUrl,
    required String layer,
    required String infoFormat,
    required double lat,
    required double lon,
    required double cellDeg,
  }) {
    final d = cellDeg * 1.5;
    String f(double v) => v.toStringAsFixed(6);
    return Uri.parse('$baseUrl?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetFeatureInfo'
        '&LAYERS=$layer&QUERY_LAYERS=$layer&STYLES=&SRS=EPSG:4326'
        '&BBOX=${f(lon - d)},${f(lat - d)},${f(lon + d)},${f(lat + d)}'
        '&WIDTH=3&HEIGHT=3&X=1&Y=1'
        '&INFO_FORMAT=${Uri.encodeQueryComponent(infoFormat)}&FEATURE_COUNT=1');
  }

  static Uri emodnetUrl(LatLng p) => featureInfoUrl(
        baseUrl: 'https://ows.emodnet-bathymetry.eu/wms',
        layer: 'emodnet:mean',
        infoFormat: 'application/json',
        lat: p.latitude,
        lon: p.longitude,
        cellDeg: _emodnetCellDeg,
      );

  /// GEBCO's MapServer only finds a cell when the queried pixel lies on a
  /// grid cell centre (points on a cell edge return "no results"), so the
  /// query is centred on the centre of the cell containing [p].
  static Uri gebcoUrl(LatLng p) {
    double centre(double v) => ((v / _gebcoCellDeg).floor() + 0.5) * _gebcoCellDeg;
    return featureInfoUrl(
      baseUrl: 'https://wms.gebco.net/mapserv',
      layer: 'GEBCO_LATEST_2',
      infoFormat: 'text/plain',
      lat: centre(p.latitude),
      lon: centre(p.longitude),
      cellDeg: _gebcoCellDeg,
    );
  }

  Future<double?> _get(Uri url, double? Function(String body) parse) async {
    final res = await _client.get(url);
    if (res.statusCode != 200) return null;
    return parse(res.body);
  }

  /// Elevation (m, positive up) from an EMODnet GeoJSON FeatureInfo body;
  /// null for no data or a non-JSON (error) body.
  static double? parseEmodnet(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final features = json['features'];
      if (features is! List || features.isEmpty) return null;
      final props = (features.first as Map)['properties'];
      if (props is! Map) return null;
      final v = props['Depth'] ?? props['depth'];
      final z = v is num ? v.toDouble() : double.tryParse('$v');
      // Exactly 0 is EMODnet's "no data" (e.g. open Atlantic).
      if (z == null || z.isNaN || z == 0) return null;
      return z;
    } catch (_) {
      return null;
    }
  }

  static final _valueList = RegExp(r"value_list\s*=\s*'(-?[0-9.]+)");

  /// Elevation (m, positive up) from a GEBCO (MapServer) text/plain
  /// FeatureInfo body; null for "Search returned no results" or errors.
  static double? parseGebco(String body) {
    final m = _valueList.firstMatch(body);
    if (m == null) return null;
    final z = double.tryParse(m.group(1)!);
    if (z == null || z.isNaN) return null;
    return z;
  }

  void close() => _client.close();
}
