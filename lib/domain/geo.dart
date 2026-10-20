import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Mean Earth radius in metres (IUGG).
const double earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180.0;
double _deg(double rad) => rad * 180.0 / math.pi;

/// Great-circle distance in metres (haversine).
double distanceM(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final la1 = _rad(a.latitude);
  final la2 = _rad(b.latitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Initial bearing from [a] to [b] in degrees, 0..360 (0 = north, clockwise).
double bearingDeg(LatLng a, LatLng b) {
  final la1 = _rad(a.latitude);
  final la2 = _rad(b.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final y = math.sin(dLon) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) -
      math.sin(la1) * math.cos(la2) * math.cos(dLon);
  return normalizeDeg(_deg(math.atan2(y, x)));
}

/// Point reached by travelling [distM] metres from [start] on [bearing] degrees.
LatLng destination(LatLng start, double bearing, double distM) {
  final d = distM / earthRadiusM;
  final b = _rad(bearing);
  final la1 = _rad(start.latitude);
  final lo1 = _rad(start.longitude);
  final la2 = math.asin(math.sin(la1) * math.cos(d) +
      math.cos(la1) * math.sin(d) * math.cos(b));
  final lo2 = lo1 +
      math.atan2(math.sin(b) * math.sin(d) * math.cos(la1),
          math.cos(d) - math.sin(la1) * math.sin(la2));
  return LatLng(_deg(la2), _normalizeLon(_deg(lo2)));
}

double normalizeDeg(double d) {
  final r = d % 360.0;
  return r < 0 ? r + 360.0 : r;
}

double _normalizeLon(double lon) => ((lon + 540.0) % 360.0) - 180.0;

/// Horizontal distance the anchor rode can reach: √(rode² − depth²).
/// Returns 0 when the rode is not longer than the depth.
double horizontalRodeM({required double rodeM, required double depthM}) {
  if (rodeM <= depthM) return 0;
  return math.sqrt(rodeM * rodeM - depthM * depthM);
}

/// Suggested alarm radius from rode, depth and boat dimensions (see DESIGN.md).
double suggestedRadiusM({
  required double rodeM,
  required double depthM,
  required double boatLengthM,
  double gpsMarginM = 5,
  double minRadiusM = 15,
}) {
  final r = horizontalRodeM(rodeM: rodeM, depthM: depthM) +
      boatLengthM +
      gpsMarginM;
  return math.max(minRadiusM, r);
}

/// Anchor position estimated from where the boat has settled: from the GPS
/// position, along the bow direction, by the horizontal rode length plus the
/// distance from the GPS antenna (phone) to the bow.
LatLng anchorFromSettledPosition({
  required LatLng boat,
  required double bowBearingDeg,
  required double rodeM,
  required double depthM,
  required double gpsToBowM,
}) {
  final dist = horizontalRodeM(rodeM: rodeM, depthM: depthM) + gpsToBowM;
  return destination(boat, bowBearingDeg, dist);
}

/// Simple local equirectangular projection used for averaging nearby points.
/// Accurate to well under a centimetre over a few hundred metres.
class LocalProjection {
  LocalProjection(this.origin)
      : _cosLat = math.cos(_rad(origin.latitude));

  final LatLng origin;
  final double _cosLat;

  /// Returns (east, north) in metres relative to [origin].
  (double, double) toXY(LatLng p) {
    // Wrap the longitude difference so points across the antimeridian stay local.
    final dLon = _normalizeLon(p.longitude - origin.longitude);
    final x = _rad(dLon) * earthRadiusM * _cosLat;
    final y = _rad(p.latitude - origin.latitude) * earthRadiusM;
    return (x, y);
  }

  LatLng fromXY(double x, double y) => LatLng(
        origin.latitude + _deg(y / earthRadiusM),
        _normalizeLon(origin.longitude + _deg(x / (earthRadiusM * _cosLat))),
      );
}
