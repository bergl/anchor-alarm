import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'geo.dart';

/// A square raster of water (true) / land-or-no-data (false) around [centre],
/// north up, in a local metric grid: pixel (x, y) covers
/// east −halfSize + x·m … +m, north halfSize − y·m … −m (row 0 = north).
///
/// Built from a WMS GetMap image (see `LandMaskService`); pure Dart so the
/// exposure analysis can be unit tested with synthetic masks.
class WaterMask {
  WaterMask({
    required this.centre,
    required this.width,
    required this.height,
    required this.metresPerPixel,
    required Uint8List water,
    this.source = '',
  })  : assert(water.length == width * height),
        _water = water,
        _proj = LocalProjection(centre);

  /// Builds a mask from text rows: `#` (or any non-`.`) = land, `.` = water.
  /// Row 0 is the northern edge. For tests and synthetic examples.
  factory WaterMask.fromRows(
    List<String> rows, {
    required LatLng centre,
    required double metresPerPixel,
    String source = 'test',
  }) {
    final h = rows.length;
    final w = rows.first.length;
    final data = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final r = rows[y];
      assert(r.length == w, 'row $y has ${r.length} chars, expected $w');
      for (var x = 0; x < w; x++) {
        data[y * w + x] = r.codeUnitAt(x) == 0x2E /* . */ ? 1 : 0;
      }
    }
    return WaterMask(
      centre: centre,
      width: w,
      height: h,
      metresPerPixel: metresPerPixel,
      water: data,
      source: source,
    );
  }

  final LatLng centre;
  final int width;
  final int height;
  final double metresPerPixel;

  /// Where the data came from, e.g. "EMODnet" or "GEBCO".
  final String source;
  final Uint8List _water;
  final LocalProjection _proj;

  double get halfWidthM => width * metresPerPixel / 2;
  double get halfHeightM => height * metresPerPixel / 2;

  /// Water pixels.
  int get waterCount => _water.fold(0, (a, b) => a + b);
  bool get allLand => !_water.contains(1);

  bool isWaterPx(int x, int y) => _water[y * width + x] == 1;

  /// Pixel containing the local point ([east], [north] metres from
  /// [centre]); null outside the mask.
  (int, int)? pixelAt(double east, double north) {
    final x = ((east + halfWidthM) / metresPerPixel).floor();
    final y = ((halfHeightM - north) / metresPerPixel).floor();
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    return (x, y);
  }

  /// Water at the local point; null outside the mask.
  bool? isWaterXY(double east, double north) {
    final p = pixelAt(east, north);
    return p == null ? null : isWaterPx(p.$1, p.$2);
  }

  /// Local (east, north) metres of [p] relative to [centre].
  (double, double) toLocal(LatLng p) => _proj.toXY(p);

  /// Water at [p]; null outside the mask.
  bool? isWaterAt(LatLng p) {
    final (e, n) = toLocal(p);
    return isWaterXY(e, n);
  }

  /// Distance from [p] to the nearest mask edge, metres (negative outside).
  double edgeDistanceM(LatLng p) {
    final (e, n) = toLocal(p);
    return math.min(halfWidthM - e.abs(), halfHeightM - n.abs());
  }

  Map<String, Object?> toJson() {
    // Bits packed 8 per byte, then base64.
    final packed = Uint8List((_water.length + 7) >> 3);
    for (var i = 0; i < _water.length; i++) {
      if (_water[i] == 1) packed[i >> 3] |= 1 << (i & 7);
    }
    return {
      'v': 1,
      'lat': centre.latitude,
      'lon': centre.longitude,
      'w': width,
      'h': height,
      'm': metresPerPixel,
      'src': source,
      'bits': base64Encode(packed),
    };
  }

  /// Null when [j] is not a valid serialised mask.
  static WaterMask? fromJson(Object? j) {
    try {
      if (j is! Map || j['v'] != 1) return null;
      final w = j['w'] as int, h = j['h'] as int;
      final packed = base64Decode(j['bits'] as String);
      if (packed.length != (w * h + 7) >> 3) return null;
      final data = Uint8List(w * h);
      for (var i = 0; i < data.length; i++) {
        data[i] = (packed[i >> 3] >> (i & 7)) & 1;
      }
      return WaterMask(
        centre: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        width: w,
        height: h,
        metresPerPixel: (j['m'] as num).toDouble(),
        water: data,
        source: j['src'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
