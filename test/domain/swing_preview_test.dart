import 'package:anchor_alarm/domain/anchoring_history.dart';
import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/swing_preview.dart';
import 'package:anchor_alarm/domain/weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const anchor = LatLng(43.1673, 16.3942);

void main() {
  group('coveringArc', () {
    test('single bearing', () => expect(coveringArc([90]), (90.0, 0.0)));
    test('simple range', () => expect(coveringArc([200, 180, 240]), (180.0, 60.0)));
    test('across north', () => expect(coveringArc([350, 10, 30]), (350.0, 40.0)));
    test('empty', () => expect(coveringArc([]), (0.0, 0.0)));
    test('arcContains', () {
      expect(arcContains(350, 40, 5), isTrue);
      expect(arcContains(350, 40, 31), isFalse);
      expect(arcContains(350, 40, 350), isTrue);
    });
  });

  test('boat lies downwind; the arc follows the wind over 12 h', () {
    final now = DateTime.utc(2026, 10, 20, 18, 20);
    final f = Forecast(
      fetchedAt: now,
      location: anchor,
      hourly: [
        for (var i = 0; i < 24; i++)
          WeatherConditions(
            time: DateTime.utc(2026, 10, 20, 18).add(Duration(hours: i)),
            windKn: 10,
            // NE (45°) veering to E (90°) over the first 12 hours, then S.
            windDirDeg: i < 12 ? 45 + i * 45 / 11 : 180,
          ),
      ],
    );
    final s = computeSwingPreview(anchor: anchor, radiusM: 30, forecast: f, now: now)!;
    // The current hour plus the next 12 (the 13th is S already).
    expect(s.points, hasLength(13));
    // Wind from NE → boat to the SW of the anchor.
    expect(s.points.first.boatBearingDeg, closeTo(225, 1e-9));
    expect(distanceM(anchor, s.points.first.position), closeTo(30, 0.01));
    expect(bearingDeg(anchor, s.points.first.position), closeTo(225, 0.01));
    expect(s.startDeg, closeTo(225, 1e-9));
    expect(s.sweepDeg, closeTo(135, 1e-9)); // 225° … 360° (wind NE → E → S)
    expect(s.arcPoints(steps: 4), hasLength(5));
  });

  test('no direction data: null', () {
    final now = DateTime.utc(2026, 10, 20, 18);
    final f = Forecast(fetchedAt: now, location: anchor, hourly: [
      WeatherConditions(time: now, windKn: 5),
    ]);
    expect(computeSwingPreview(anchor: anchor, radiusM: 30, forecast: f, now: now), isNull);
  });

  group('historyNear', () {
    AnchorSession s(String id, LatLng p, {bool drag = false, String? name, int day = 1}) =>
        AnchorSession(
          id: id,
          anchor: p,
          radiusM: 40,
          initialRadiusM: 40,
          profile: AlarmProfile.builtIns[1],
          startedAt: DateTime.utc(2026, 8, day),
          endedAt: DateTime.utc(2026, 8, day, 8),
          name: name,
          alerts: [
            if (drag) AlertEvent(reason: AlertReason.drag, time: DateTime.utc(2026, 8, day, 3)),
          ],
        );

    test('counts sessions within 500 m and drag alarms', () {
      final h = historyNear([
        s('a', destination(anchor, 90, 200), name: 'Palmižana', day: 3),
        s('b', destination(anchor, 0, 450), day: 2),
        s('c', destination(anchor, 0, 800), drag: true),
      ], anchor);
      expect(h.sessions, 2);
      expect(h.dragAlarms, 0);
      expect(h.text, 'You anchored here (Palmižana) 2× before, no drag alarms');
    });

    test('drag alarms are reported', () {
      final h = historyNear([s('a', anchor, drag: true), s('b', anchor, day: 5)], anchor);
      expect(h.text, 'You anchored here 2× before, drag alarm once');
      expect(h.lastDrag, DateTime.utc(2026, 8, 1));
    });

    test('nothing nearby', () => expect(historyNear([], anchor).text, isNull));
  });
}
