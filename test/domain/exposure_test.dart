import 'package:anchor_alarm/domain/exposure.dart';
import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/water_mask.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const centre = LatLng(43.0, 16.0);

/// 9 km square, 100 m pixels; [land] gets local (east, north) metres of the
/// pixel centre.
WaterMask synthetic(bool Function(double e, double n) land, {int px = 90, double m = 100}) {
  final rows = <String>[];
  for (var y = 0; y < px; y++) {
    final b = StringBuffer();
    for (var x = 0; x < px; x++) {
      final e = -px * m / 2 + (x + 0.5) * m;
      final n = px * m / 2 - (y + 0.5) * m;
      b.write(land(e, n) ? '#' : '.');
    }
    rows.add(b.toString());
  }
  return WaterMask.fromRows(rows, centre: centre, metresPerPixel: m);
}

SectorExposure sector(ExposureProfile p, String name) =>
    p.sectors[compass16.indexOf(name)];

void main() {
  group('sectorIndex', () {
    test('maps directions to the 16 compass points', () {
      expect(sectorIndex(0), 0);
      expect(sectorIndex(11.2), 0);
      expect(sectorIndex(11.3), 1);
      expect(sectorIndex(350), 0);
      expect(sectorIndex(-10), 0);
      expect(sectorIndex(180), 8);
      expect(sectorIndex(225), 10);
      expect(sectorIndex(359.9), 0);
      expect(compass16Name(202.5), 'SSW');
      expect(compass16Name(225), 'SW');
    });
  });

  group('describeSectorRanges', () {
    test('groups consecutive sectors, wrapping at north', () {
      expect(describeSectorRanges([0, 1, 2, 3, 4, 10]), 'N–E, SW');
      expect(describeSectorRanges([15, 0, 1]), 'NNW–NNE');
      expect(describeSectorRanges([8]), 'S');
      expect(describeSectorRanges(List.generate(16, (i) => i)), 'all directions');
      expect(describeSectorRanges([]), '');
    });
  });

  group('computeExposure', () {
    test('bay open to the south', () {
      // Land north of 300 m, and on both sides (|east| > 400 m) down to
      // 800 m south: a bay whose mouth faces south.
      final mask = synthetic((e, n) => n > 300 || (e.abs() > 400 && n > -800));
      final p = computeExposure(mask, centre)!;
      expect(p.anchorOnLand, isFalse);
      expect(sector(p, 'N').rating, ShelterRating.sheltered);
      expect(sector(p, 'N').fetchM, closeTo(350, 60));
      expect(sector(p, 'E').rating, ShelterRating.sheltered);
      expect(sector(p, 'W').rating, ShelterRating.sheltered);
      expect(sector(p, 'S').rating, ShelterRating.exposed);
      expect(sector(p, 'S').capped, isTrue);
      expect(sector(p, 'S').fetchM, 4000);
      // Diagonals hit the bay sides.
      expect(sector(p, 'SE').rating, ShelterRating.partly);
      expect(sector(p, 'SW').rating, ShelterRating.partly);

      // Wind from the south blows straight into the bay.
      final south = p.forWindFrom(185);
      expect(south.sector.name, 'S');
      expect(south.rating, ShelterRating.exposed);
      expect(p.forWindFrom(10).rating, ShelterRating.sheltered);
      expect(p.describe(), contains('Sheltered from'));
      expect(p.describe(), contains('Exposed to SSE–SSW (fetch > 4.0 km)'));
    });

    test('island to the south shelters only that side', () {
      // Island of radius 500 m centred 1.5 km south: its shore is 1 km away.
      final mask = synthetic((e, n) => e * e + (n + 1500) * (n + 1500) < 500 * 500);
      final p = computeExposure(mask, centre)!;
      final s = sector(p, 'S');
      expect(s.rating, ShelterRating.partly);
      expect(s.fetchM, closeTo(1000, 120));
      for (final name in ['N', 'E', 'W', 'NE', 'NW']) {
        expect(sector(p, name).rating, ShelterRating.exposed, reason: name);
        expect(sector(p, name).capped, isTrue, reason: name);
      }
      expect(p.forWindFrom(180).rating, ShelterRating.partly);
      expect(p.forWindFrom(0).rating, ShelterRating.exposed);
    });

    test('open sea: exposed all round', () {
      final p = computeExposure(synthetic((e, n) => false), centre)!;
      expect(p.sectors.every((s) => s.rating == ShelterRating.exposed && s.capped), isTrue);
      expect(p.describe(), 'Open water all round — no shelter.');
    });

    test('enclosed: sheltered all round', () {
      final p = computeExposure(synthetic((e, n) => e * e + n * n > 250 * 250), centre)!;
      expect(p.sectors.every((s) => s.rating == ShelterRating.sheltered), isTrue);
      expect(p.describe(), 'Sheltered all round.');
    });

    test('a one-pixel islet does not close a whole sector', () {
      // 100 m islet 300 m north; the sector's side rays pass it.
      final mask = synthetic((e, n) => e.abs() < 50 && n > 250 && n < 350);
      final p = computeExposure(mask, centre)!;
      expect(sector(p, 'N').rating, isNot(ShelterRating.sheltered));
    });

    test('anchor on a coastline cell skips the first land', () {
      // Anchor in a land cell at the shore; water starts 100 m south.
      final mask = synthetic((e, n) => n > -100);
      final p = computeExposure(mask, centre)!;
      expect(p.anchorOnLand, isTrue);
      expect(sector(p, 'S').rating, ShelterRating.exposed);
      expect(sector(p, 'N').fetchM, 0);
      expect(sector(p, 'N').rating, ShelterRating.sheltered);
    });

    test('outside the mask: null', () {
      final mask = synthetic((e, n) => false);
      expect(computeExposure(mask, destination(centre, 0, 6000)), isNull);
    });

    test('thresholds are inclusive lower bounds', () {
      const t = ExposureThresholds();
      expect(t.rate(499), ShelterRating.sheltered);
      expect(t.rate(500), ShelterRating.partly);
      expect(t.rate(1999), ShelterRating.partly);
      expect(t.rate(2000), ShelterRating.exposed);
    });
  });

  group('WaterMask', () {
    test('JSON round trip', () {
      final mask = synthetic((e, n) => n > 1000 || e < -2000, px: 37);
      final back = WaterMask.fromJson(mask.toJson())!;
      expect(back.width, 37);
      expect(back.metresPerPixel, 100);
      expect(back.centre, centre);
      for (var y = 0; y < 37; y++) {
        for (var x = 0; x < 37; x++) {
          expect(back.isWaterPx(x, y), mask.isWaterPx(x, y));
        }
      }
      expect(WaterMask.fromJson({'v': 2}), isNull);
      expect(WaterMask.fromJson('junk'), isNull);
    });

    test('pixel geometry: row 0 is north', () {
      final mask = WaterMask.fromRows(['#.', '..'], centre: centre, metresPerPixel: 100);
      expect(mask.isWaterXY(-50, 50), isFalse); // NW pixel
      expect(mask.isWaterXY(50, 50), isTrue);
      expect(mask.isWaterXY(-50, -50), isTrue);
      expect(mask.isWaterXY(150, 0), isNull);
      expect(mask.isWaterAt(destination(centre, 315, 70)), isFalse);
    });
  });
}
