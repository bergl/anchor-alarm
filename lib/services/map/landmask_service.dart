import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

import '../../domain/water_mask.dart';
import 'landmask_store.dart';
import 'tile_layer_spec.dart' show TileLayerSpec, tileUserAgent;

export 'landmask_store.dart' show LandMaskStore, MemoryLandMaskStore, createLandMaskStore;

/// Water / land raster around a position, for the shelter analysis.
///
/// One WMS GetMap request (EPSG:3857, PNG) for a square of [sizeM] around
/// the centre, rounded to [roundDeg] so nearby positions share one mask:
///
/// 1. EMODnet `emodnet:mean_multicolour`: water pixels are opaque, land and
///    "no data" are fully transparent (alpha 0) → water = alpha ≥ 128.
///    Outside EMODnet coverage (open Atlantic, outside Europe) the whole
///    image is transparent.
/// 2. If EMODnet fails or shows no water at all: GEBCO `GEBCO_LATEST_2`
///    (global, opaque colour ramp): water is drawn in blues/cyans where blue
///    exceeds red and is at least ¾ of green; land is green → yellow → brown
///    → white. Rule `water = B > R && 4·B ≥ 3·G` agrees with EMODnet on ~98 %
///    of pixels over the central Mediterranean (misses are the palest,
///    shallowest coastal cells).
///
/// Masks are cached in memory (last [memoryEntries]) and in [store] (disk on
/// mobile). Never throws: returns null when offline / on errors / after
/// [timeout].
class LandMaskService {
  LandMaskService({
    http.Client? client,
    LandMaskStore? store,
    this.timeout = const Duration(seconds: 10),
    this.sizeM = 9000,
    this.pixels = 180,
    this.roundDeg = 0.005,
    this.memoryEntries = 12,
  })  : _client = client ?? http.Client(),
        _store = store ?? MemoryLandMaskStore();

  final http.Client _client;
  final LandMaskStore _store;
  final Duration timeout;

  /// Side of the square, metres on the ground (9 km: 4 km fetch radius with
  /// room for the rounding of the centre).
  final double sizeM;

  /// Image width and height (180 px → 50 m per pixel).
  final int pixels;

  /// Centre rounding, degrees (≈ 550 m north–south).
  final double roundDeg;
  final int memoryEntries;

  static const emodnetSource = 'EMODnet';
  static const gebcoSource = 'GEBCO';
  static const emodnetLayer = 'emodnet:mean_multicolour';
  static const gebcoLayer = 'GEBCO_LATEST_2';

  final _memory = <String, WaterMask>{};
  final _pending = <String, Future<WaterMask?>>{};

  double get metresPerPixel => sizeM / pixels;

  /// Mask centre used for [p].
  LatLng roundedCentre(LatLng p) {
    double r(double v) => double.parse(((v / roundDeg).round() * roundDeg).toStringAsFixed(6));
    return LatLng(r(p.latitude), r(p.longitude));
  }

  String cacheKey(LatLng centre) =>
      '${centre.latitude.toStringAsFixed(4)}_${centre.longitude.toStringAsFixed(4)}_'
      '${sizeM.round()}_$pixels';

  /// Cached mask for [p] without any request (null when not cached in memory).
  WaterMask? cached(LatLng p) => _memory[cacheKey(roundedCentre(p))];

  /// The water mask around [p] (its centre is [roundedCentre]).
  Future<WaterMask?> maskAround(LatLng p) {
    final centre = roundedCentre(p);
    final key = cacheKey(centre);
    final hit = _memory[key];
    if (hit != null) {
      // LRU: move to the end.
      _memory.remove(key);
      _memory[key] = hit;
      return Future.value(hit);
    }
    // (A block body: `=> _pending.remove(key)` would return this very future
    // and whenComplete would wait for itself.)
    return _pending[key] ??= _load(centre, key).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<WaterMask?> _load(LatLng centre, String key) async {
    try {
      final stored = WaterMask.fromJson(await _store.read(key));
      final mask = stored ?? await _fetch(centre);
      if (mask == null) return null;
      _remember(key, mask);
      if (stored == null) {
        unawaited(_store.write(key, mask.toJson()).catchError((_) {}));
      }
      return mask;
    } catch (_) {
      return null;
    }
  }

  void _remember(String key, WaterMask m) {
    _memory[key] = m;
    while (_memory.length > memoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<WaterMask?> _fetch(LatLng centre) async {
    final e = await _get(emodnetUrl(centre));
    final emodnet = e == null ? null : decodeEmodnet(e, centre, metresPerPixel);
    if (emodnet != null && !emodnet.allLand) return emodnet;
    final g = await _get(gebcoUrl(centre));
    final gebco = g == null ? null : decodeGebco(g, centre, metresPerPixel);
    // All land in both: genuinely inland. Prefer the finer EMODnet answer.
    return gebco ?? emodnet;
  }

  Future<Uint8List?> _get(Uri url) async {
    try {
      final res = await _client
          .get(url, headers: const {'User-Agent': tileUserAgent})
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final type = res.headers['content-type'] ?? '';
      if (!type.startsWith('image/png')) return null; // e.g. XML exception
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  static const _r = 6378137.0;

  /// EPSG:3857 bbox of a square [sizeM] on the ground around [c]
  /// (Web Mercator stretches distances by 1 / cos(lat)).
  String bbox(LatLng c) {
    final x = _r * c.longitude * math.pi / 180;
    final y = _r * math.log(math.tan(math.pi / 4 + c.latitude * math.pi / 360));
    final h = sizeM / 2 / math.cos(c.latitude * math.pi / 180);
    String f(double v) => v.toStringAsFixed(2);
    return '${f(x - h)},${f(y - h)},${f(x + h)},${f(y + h)}';
  }

  Uri _getMap(String base, String layer, LatLng c, {bool transparent = true}) =>
      Uri.parse('$base?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap'
          '&LAYERS=$layer&STYLES=&SRS=EPSG:3857&BBOX=${bbox(c)}'
          '&WIDTH=$pixels&HEIGHT=$pixels&FORMAT=image/png'
          '${transparent ? '&TRANSPARENT=true' : ''}');

  Uri emodnetUrl(LatLng c) => _getMap(TileLayerSpec.emodnetWmsUrl, emodnetLayer, c);

  Uri gebcoUrl(LatLng c) =>
      _getMap(TileLayerSpec.gebcoWmsUrl, gebcoLayer, c, transparent: false);

  /// EMODnet: water = opaque pixel. Null when [png] is not a decodable PNG.
  static WaterMask? decodeEmodnet(Uint8List png, LatLng centre, double metresPerPixel) =>
      _decode(png, centre, metresPerPixel, emodnetSource, (p) => p.aNormalized >= 0.5);

  /// GEBCO: water = blue/cyan colour (B > R and 4·B ≥ 3·G).
  static WaterMask? decodeGebco(Uint8List png, LatLng centre, double metresPerPixel) =>
      _decode(png, centre, metresPerPixel, gebcoSource, (p) {
        if (p.aNormalized < 0.5) return false;
        final r = p.rNormalized, g = p.gNormalized, b = p.bNormalized;
        return b > r && 4 * b >= 3 * g;
      });

  static WaterMask? _decode(Uint8List png, LatLng centre, double metresPerPixel,
      String source, bool Function(img.Pixel p) isWater) {
    try {
      final image = img.decodePng(png);
      if (image == null) return null;
      final w = image.width, h = image.height;
      final data = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (isWater(image.getPixel(x, y))) data[y * w + x] = 1;
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
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
