import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'water_mask.dart';

/// How well an anchorage is protected from one direction, by the distance of
/// open water (fetch) the wind and waves have in that direction.
enum ShelterRating {
  /// Fetch under [ExposureThresholds.shelteredBelowM]: land close by.
  sheltered,

  /// Fetch under [ExposureThresholds.exposedFromM]: some chop builds up.
  partly,

  /// Long fetch: waves build up and roll into the anchorage.
  exposed,
}

/// Fetch limits for the ratings (inclusive lower bounds).
class ExposureThresholds {
  const ExposureThresholds({
    this.shelteredBelowM = 500,
    this.exposedFromM = 2000,
    this.maxFetchM = 4000,
  });

  final double shelteredBelowM;
  final double exposedFromM;

  /// Rays stop here (≈ the radius the land mask covers).
  final double maxFetchM;

  ShelterRating rate(double fetchM) => fetchM < shelteredBelowM
      ? ShelterRating.sheltered
      : fetchM < exposedFromM
          ? ShelterRating.partly
          : ShelterRating.exposed;
}

/// The 16 compass points, clockwise from north.
const compass16 = [
  'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
  'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
];

/// Width of one of the 16 sectors, degrees.
const sectorWidthDeg = 22.5;

/// Index (0 = N … 15 = NNW) of the sector containing direction [deg].
int sectorIndex(double deg) =>
    (((deg % 360) + 360 + sectorWidthDeg / 2) % 360 ~/ sectorWidthDeg) % 16;

/// 16-point compass name for [deg].
String compass16Name(double deg) => compass16[sectorIndex(deg)];

/// Open water in one of the 16 directions from the anchor.
class SectorExposure {
  const SectorExposure({
    required this.index,
    required this.fetchM,
    required this.rating,
    required this.capped,
  });

  /// 0 = N, 1 = NNE … 15 = NNW.
  final int index;

  /// Mean open-water distance of the rays in this sector, metres.
  final double fetchM;
  final ShelterRating rating;

  /// Every ray reached the analysis radius without meeting land: the real
  /// fetch is at least [fetchM].
  final bool capped;

  double get bearingDeg => index * sectorWidthDeg;
  String get name => compass16[index];

  @override
  String toString() => 'SectorExposure($name ${fetchM.round()} m ${rating.name})';
}

/// Wind from one direction evaluated against an [ExposureProfile].
class WindExposure {
  const WindExposure({required this.fromDeg, required this.sector});

  /// Direction the wind comes FROM, degrees.
  final double fromDeg;

  /// The upwind sector: open water the wind blows across before reaching
  /// the anchor.
  final SectorExposure sector;

  double get fetchM => sector.fetchM;
  ShelterRating get rating => sector.rating;
}

/// Fetch in all 16 directions around an anchor position.
class ExposureProfile {
  const ExposureProfile({
    required this.anchor,
    required this.sectors,
    required this.thresholds,
    this.source = '',
    this.anchorOnLand = false,
  });

  final LatLng anchor;

  /// Exactly 16, index 0 = N.
  final List<SectorExposure> sectors;
  final ExposureThresholds thresholds;

  /// Data source of the land mask ("EMODnet", "GEBCO").
  final String source;

  /// The anchor lies in a land / no-data cell of the grid (on the
  /// coastline): the first ~150 m of land along each ray were skipped.
  final bool anchorOnLand;

  /// Upwind fetch and rating for wind blowing FROM [fromDeg].
  WindExposure forWindFrom(double fromDeg) =>
      WindExposure(fromDeg: fromDeg, sector: sectors[sectorIndex(fromDeg)]);

  List<SectorExposure> withRating(ShelterRating r) =>
      [for (final s in sectors) if (s.rating == r) s];

  /// Shelter by sector in words, e.g. "Sheltered from N–E. Partly open
  /// to SE. Exposed to S–W (fetch 3.8 km)."
  String describe() {
    final parts = <String>[];
    String range(ShelterRating r) => describeSectorRanges([
          for (final s in sectors) if (s.rating == r) s.index,
        ]);
    final sheltered = withRating(ShelterRating.sheltered);
    final partly = withRating(ShelterRating.partly);
    final exposed = withRating(ShelterRating.exposed);
    if (sheltered.length == 16) return 'Sheltered all round.';
    if (exposed.length == 16) return 'Open water all round — no shelter.';
    if (sheltered.isNotEmpty) parts.add('Sheltered from ${range(ShelterRating.sheltered)}.');
    if (partly.isNotEmpty) parts.add('Partly open to ${range(ShelterRating.partly)}.');
    if (exposed.isNotEmpty) {
      final longest = exposed.map((s) => s.fetchM).reduce(math.max);
      final capped = exposed.any((s) => s.capped);
      parts.add('Exposed to ${range(ShelterRating.exposed)} '
          '(fetch ${capped ? '> ' : ''}${formatFetch(longest)}).');
    }
    return parts.join(' ');
  }
}

/// "3.8 km" / "450 m".
String formatFetch(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${(m / 50).round() * 50} m';

/// Consecutive sector indices (wrapping at north) as ranges, e.g.
/// [0, 1, 2, 3, 4, 10] → "N–E, SW".
String describeSectorRanges(List<int> indices) {
  if (indices.isEmpty) return '';
  final set = indices.toSet();
  if (set.length == 16) return 'all directions';
  // Start right after a gap so a range across north stays in one piece.
  var start = 0;
  while (set.contains(start)) {
    start = (start + 1) % 16;
  }
  final ranges = <(int, int)>[];
  int? first;
  int? last;
  for (var k = 1; k <= 16; k++) {
    final i = (start + k) % 16;
    if (set.contains(i)) {
      first ??= i;
      last = i;
    } else if (first != null) {
      ranges.add((first, last!));
      first = null;
    }
  }
  // Clockwise from north; a range across north comes first.
  ranges.sort((a, b) {
    final wa = a.$1 > a.$2 ? -1 : a.$1, wb = b.$1 > b.$2 ? -1 : b.$1;
    return wa.compareTo(wb);
  });
  return [
    for (final (f, l) in ranges) f == l ? compass16[f] : '${compass16[f]}–${compass16[l]}',
  ].join(', ');
}

/// Ray offsets within a sector, degrees: the sector fetch is the mean of
/// these rays, so a narrow gap between islands counts for its width and a
/// one-pixel islet does not close a whole sector.
const _rayOffsets = [-8.0, -4.0, 0.0, 4.0, 8.0];

/// Land this close to an anchor that sits on a land/no-data grid cell is
/// treated as the coastline cell itself and skipped.
const coastSkipM = 150.0;

/// Fetch in 16 directions from [anchor] by marching rays across [mask]
/// (step = half a pixel) until they meet land, leave the mask or reach
/// [ExposureThresholds.maxFetchM]. Null when [anchor] is outside the mask.
ExposureProfile? computeExposure(
  WaterMask mask,
  LatLng anchor, {
  ExposureThresholds thresholds = const ExposureThresholds(),
}) {
  final (e0, n0) = mask.toLocal(anchor);
  final here = mask.isWaterXY(e0, n0);
  if (here == null) return null;
  final onLand = !here;
  final maxM = thresholds.maxFetchM;
  final step = mask.metresPerPixel / 2;

  double ray(double bearingDeg) {
    final b = bearingDeg * math.pi / 180;
    final dx = math.sin(b), dy = math.cos(b);
    var started = !onLand;
    for (var d = step; d < maxM; d += step) {
      final w = mask.isWaterXY(e0 + dx * d, n0 + dy * d);
      if (w == null) return d; // Left the mask: open as far as we know.
      if (!started) {
        if (w) {
          started = true;
        } else if (d > coastSkipM) {
          return 0;
        }
        continue;
      }
      if (!w) return d;
    }
    return maxM;
  }

  final sectors = <SectorExposure>[];
  for (var i = 0; i < 16; i++) {
    final rays = [for (final o in _rayOffsets) ray(i * sectorWidthDeg + o)];
    final fetch = rays.reduce((a, b) => a + b) / rays.length;
    sectors.add(SectorExposure(
      index: i,
      fetchM: fetch,
      rating: thresholds.rate(fetch),
      capped: rays.every((r) => r >= maxM),
    ));
  }
  return ExposureProfile(
    anchor: anchor,
    sectors: sectors,
    thresholds: thresholds,
    source: mask.source,
    anchorOnLand: onLand,
  );
}
