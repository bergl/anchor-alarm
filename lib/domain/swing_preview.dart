import 'package:latlong2/latlong.dart';

import 'geo.dart';
import 'weather.dart';
import 'weather_risk.dart' show signedAngleDiff;

/// Where the boat will lie in one forecast hour.
class SwingPoint {
  const SwingPoint({
    required this.time,
    required this.windFromDeg,
    required this.boatBearingDeg,
    required this.position,
    this.windKn,
  });

  final DateTime time;
  final double windFromDeg;

  /// Bearing anchor → boat (downwind: [windFromDeg] + 180°).
  final double boatBearingDeg;
  final LatLng position;
  final double? windKn;
}

/// The arc a boat at anchor sweeps as the forecast wind direction changes.
class SwingPreview {
  const SwingPreview({
    required this.anchor,
    required this.radiusM,
    required this.points,
    required this.startDeg,
    required this.sweepDeg,
  });

  final LatLng anchor;

  /// Distance anchor → boat (horizontal rode length), metres.
  final double radiusM;
  final List<SwingPoint> points;

  /// The swept arc: from [startDeg] clockwise by [sweepDeg] (bearings from
  /// the anchor; 0 when the wind holds one direction).
  final double startDeg;
  final double sweepDeg;

  /// Points along the arc (for drawing), [steps] + 1 of them.
  List<LatLng> arcPoints({double? radiusM, int steps = 24}) => [
        for (var i = 0; i <= steps; i++)
          destination(anchor, startDeg + sweepDeg * i / steps, radiusM ?? this.radiusM),
      ];
}

/// Smallest arc (start, sweep) containing all [bearings]: the complement of
/// the largest gap between them.
(double, double) coveringArc(List<double> bearings) {
  if (bearings.isEmpty) return (0, 0);
  final b = [for (final x in bearings) normalizeDeg(x)]..sort();
  if (b.length == 1) return (b.first, 0);
  var gap = 360 - b.last + b.first; // wrap gap: last → first
  var start = b.first;
  for (var i = 1; i < b.length; i++) {
    final g = b[i] - b[i - 1];
    if (g > gap) {
      gap = g;
      start = b[i];
    }
  }
  return (start, 360 - gap);
}

/// The boat's expected positions over the next [horizon] of [forecast]: it
/// lies downwind of [anchor] at [radiusM] (the horizontal rode). Hours
/// without a wind direction are skipped. Null without any usable hour.
SwingPreview? computeSwingPreview({
  required LatLng anchor,
  required double radiusM,
  required Forecast forecast,
  required DateTime now,
  Duration horizon = const Duration(hours: 12),
}) {
  now = now.toUtc();
  final hourStart = DateTime.utc(now.year, now.month, now.day, now.hour);
  final end = now.add(horizon);
  final points = <SwingPoint>[];
  for (final h in forecast.hourly) {
    if (h.time.isBefore(hourStart) || !h.time.isBefore(end)) continue;
    final from = h.windDirDeg;
    if (from == null) continue;
    final bearing = normalizeDeg(from + 180);
    points.add(SwingPoint(
      time: h.time,
      windFromDeg: from,
      boatBearingDeg: bearing,
      position: destination(anchor, bearing, radiusM),
      windKn: h.windKn,
    ));
  }
  if (points.isEmpty) return null;
  final (start, sweep) = coveringArc([for (final p in points) p.boatBearingDeg]);
  return SwingPreview(
    anchor: anchor,
    radiusM: radiusM,
    points: points,
    startDeg: start,
    sweepDeg: sweep,
  );
}

/// Whether [deg] lies within the arc starting at [startDeg] sweeping
/// [sweepDeg] clockwise.
bool arcContains(double startDeg, double sweepDeg, double deg) {
  final d = signedAngleDiff(startDeg, deg);
  final off = d < 0 ? d + 360 : d;
  return off <= sweepDeg + 1e-9;
}
