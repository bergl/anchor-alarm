import 'dart:math' as math;

import 'package:anchor_alarm/domain/geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('distanceM', () {
    test('one minute of latitude is about one nautical mile', () {
      final d = distanceM(const LatLng(43, 16), const LatLng(43 + 1 / 60, 16));
      // Spherical model: 1' = R * pi / 10800 = 1853.2 m.
      expect(d, closeTo(1852, 3));
    });

    test('one minute of longitude scales with cos(lat)', () {
      final d = distanceM(const LatLng(60, 10), const LatLng(60, 10 + 1 / 60));
      expect(d, closeTo(1853.2 * 0.5, 1));
    });

    test('zero for identical points and symmetric', () {
      const a = LatLng(43.1633, 16.3972);
      const b = LatLng(43.1641, 16.3990);
      expect(distanceM(a, a), 0);
      expect(distanceM(a, b), closeTo(distanceM(b, a), 1e-9));
    });

    test('short distance across the antimeridian', () {
      final d = distanceM(const LatLng(-16.8, 179.9999), const LatLng(-16.8, -179.9999));
      expect(d, closeTo(2 * 0.0001 * 111195 * math.cos(16.8 * math.pi / 180), 0.5));
    });

    test('known long distance: Split to Ancona about 236 km', () {
      final d = distanceM(const LatLng(43.5081, 16.4402), const LatLng(43.6158, 13.5189));
      expect(d, closeTo(236000, 3000));
    });

    test('antipodes do not produce NaN', () {
      final d = distanceM(const LatLng(10, 20), const LatLng(-10, -160));
      expect(d, closeTo(math.pi * earthRadiusM, 1));
    });
  });

  group('bearingDeg', () {
    const o = LatLng(43, 16);
    test('cardinal directions', () {
      expect(bearingDeg(o, const LatLng(43.01, 16)), closeTo(0, 1e-6));
      expect(bearingDeg(o, const LatLng(43, 16.01)), closeTo(90, 0.01));
      expect(bearingDeg(o, const LatLng(42.99, 16)), closeTo(180, 1e-6));
      expect(bearingDeg(o, const LatLng(43, 15.99)), closeTo(270, 0.01));
    });

    test('always in [0, 360)', () {
      for (var b = 0.0; b < 360; b += 7.5) {
        final p = destination(o, b, 50);
        final r = bearingDeg(o, p);
        expect(r, greaterThanOrEqualTo(0));
        expect(r, lessThan(360));
      }
    });

    test('across the antimeridian eastwards', () {
      expect(bearingDeg(const LatLng(0, 179.999), const LatLng(0, -179.999)),
          closeTo(90, 1e-6));
    });
  });

  group('destination', () {
    test('round trip distance and bearing at many bearings and latitudes', () {
      for (final lat in [-70.0, -43.0, 0.0, 43.1633, 78.2]) {
        final start = LatLng(lat, 16.3972);
        for (var b = 0.0; b < 360; b += 15) {
          for (final d in [1.0, 25.0, 60.0, 500.0]) {
            final p = destination(start, b, d);
            expect(distanceM(start, p), closeTo(d, 1e-6 * d + 1e-6));
            final back = bearingDeg(start, p);
            final diff = ((back - b + 540) % 360) - 180;
            expect(diff.abs(), lessThan(1e-6), reason: 'lat $lat b $b d $d');
          }
        }
      }
    });

    test('1852 m north is about one minute of latitude', () {
      final p = destination(const LatLng(0, 0), 0, 1852);
      expect(p.latitude * 60, closeTo(1, 0.001));
      expect(p.longitude, closeTo(0, 1e-12));
    });

    test('wraps longitude across the antimeridian', () {
      final p = destination(const LatLng(-16.8, 179.9999), 90, 100);
      expect(p.longitude, lessThan(-179.99));
      expect(p.longitude, greaterThanOrEqualTo(-180));
      expect(distanceM(const LatLng(-16.8, 179.9999), p), closeTo(100, 1e-6));
    });

    test('high latitude (Svalbard) round trip', () {
      const s = LatLng(79.9, 15);
      final p = destination(s, 270, 40);
      expect(distanceM(s, p), closeTo(40, 1e-6));
    });

    test('zero distance returns the start', () {
      const s = LatLng(43.1633, 16.3972);
      final p = destination(s, 123, 0);
      expect(p.latitude, closeTo(s.latitude, 1e-12));
      expect(p.longitude, closeTo(s.longitude, 1e-12));
    });
  });

  group('normalizeDeg', () {
    test('wraps into [0, 360)', () {
      expect(normalizeDeg(0), 0);
      expect(normalizeDeg(360), 0);
      expect(normalizeDeg(-10), 350);
      expect(normalizeDeg(725), 5);
      expect(normalizeDeg(-720), 0);
    });
  });

  group('horizontalRodeM', () {
    test('pythagoras', () {
      expect(horizontalRodeM(rodeM: 50, depthM: 30), closeTo(40, 1e-9));
    });
    test('rode equal to or shorter than depth gives 0', () {
      expect(horizontalRodeM(rodeM: 5, depthM: 5), 0);
      expect(horizontalRodeM(rodeM: 3, depthM: 5), 0);
    });
    test('zero depth gives the rode', () {
      expect(horizontalRodeM(rodeM: 30, depthM: 0), 30);
    });
  });

  group('suggestedRadiusM', () {
    test('rode + boat + margin', () {
      expect(suggestedRadiusM(rodeM: 50, depthM: 30, boatLengthM: 12), closeTo(57, 1e-9));
    });
    test('custom margin', () {
      expect(suggestedRadiusM(rodeM: 50, depthM: 30, boatLengthM: 12, gpsMarginM: 0),
          closeTo(52, 1e-9));
    });
    test('never below the minimum radius', () {
      expect(suggestedRadiusM(rodeM: 2, depthM: 5, boatLengthM: 3, gpsMarginM: 2), 15);
      expect(suggestedRadiusM(rodeM: 0, depthM: 0, boatLengthM: 0, gpsMarginM: 0), 15);
      expect(
          suggestedRadiusM(rodeM: 2, depthM: 5, boatLengthM: 3, minRadiusM: 25), 25);
    });
    test('rode <= depth still includes boat and margin', () {
      expect(suggestedRadiusM(rodeM: 5, depthM: 10, boatLengthM: 14), 19);
    });
  });

  group('anchorFromSettledPosition', () {
    test('anchor is upwind along the bow by horizontal rode + gps-to-bow', () {
      const boat = LatLng(43.1633, 16.3972);
      final a = anchorFromSettledPosition(
          boat: boat, bowBearingDeg: 45, rodeM: 50, depthM: 30, gpsToBowM: 6);
      expect(distanceM(boat, a), closeTo(46, 1e-6));
      expect(bearingDeg(boat, a), closeTo(45, 1e-6));
    });
    test('short rode: only the gps-to-bow offset', () {
      const boat = LatLng(43.1633, 16.3972);
      final a = anchorFromSettledPosition(
          boat: boat, bowBearingDeg: 200, rodeM: 4, depthM: 8, gpsToBowM: 6);
      expect(distanceM(boat, a), closeTo(6, 1e-6));
    });
  });

  group('LocalProjection', () {
    test('round trip and metric distances near the origin', () {
      for (final origin in const [
        LatLng(43.1633, 16.3972),
        LatLng(0, 0),
        LatLng(-33.86, 151.2),
        LatLng(78.2, 15.6),
      ]) {
        final proj = LocalProjection(origin);
        final (x0, y0) = proj.toXY(origin);
        expect(x0, 0);
        expect(y0, 0);
        for (var b = 0.0; b < 360; b += 30) {
          final p = destination(origin, b, 200);
          final (x, y) = proj.toXY(p);
          expect(math.sqrt(x * x + y * y), closeTo(200, 0.05),
              reason: 'origin $origin bearing $b');
          final back = proj.fromXY(x, y);
          expect(back.latitude, closeTo(p.latitude, 1e-10));
          expect(back.longitude, closeTo(p.longitude, 1e-10));
        }
      }
    });

    test('east is +x and north is +y', () {
      const o = LatLng(43, 16);
      final proj = LocalProjection(o);
      final (xe, ye) = proj.toXY(destination(o, 90, 10));
      expect(xe, closeTo(10, 0.01));
      expect(ye.abs(), lessThan(0.01));
      final (xn, yn) = proj.toXY(destination(o, 0, 10));
      expect(yn, closeTo(10, 0.01));
      expect(xn.abs(), lessThan(0.01));
    });

    test('works across the antimeridian (Fiji)', () {
      const o = LatLng(-16.8, 179.9998);
      final proj = LocalProjection(o);
      final p = destination(o, 90, 50); // longitude wraps to -179.99...
      expect(p.longitude, lessThan(0));
      final (x, y) = proj.toXY(p);
      expect(x, closeTo(50, 0.05));
      expect(y.abs(), lessThan(0.05));
      final back = proj.fromXY(x, y);
      expect(distanceM(back, p), lessThan(0.01));
      expect(back.longitude, inInclusiveRange(-180, 180));
      // Point west of the origin on the other side round-trips too.
      final (xw, _) = proj.toXY(destination(o, 270, 50));
      expect(xw, closeTo(-50, 0.05));
    });
  });
}
