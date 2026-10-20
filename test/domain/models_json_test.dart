import 'dart:convert';

import 'package:anchor_alarm/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Through a real JSON string, as storage would.
Map<String, Object?> viaJson(Map<String, Object?> m) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(m)) as Map);

void main() {
  final t = DateTime(2026, 10, 20, 22, 15, 30, 123);

  group('PositionFix', () {
    test('round trip with all fields', () {
      final f = PositionFix(
        position: const LatLng(43.1633, 16.3972),
        accuracyM: 4.5,
        time: t,
        speedMps: 0.3,
        courseDeg: 271.5,
        source: FixSource.simulated,
      );
      final g = PositionFix.fromJson(viaJson(f.toJson()));
      expect(g.position, f.position);
      expect(g.accuracyM, 4.5);
      expect(g.time, t);
      expect(g.speedMps, 0.3);
      expect(g.courseDeg, 271.5);
      expect(g.source, FixSource.simulated);
    });

    test('round trip with nulls and integer-valued doubles', () {
      final f = PositionFix(position: const LatLng(43, 16), accuracyM: 5, time: t);
      final j = viaJson(f.toJson());
      expect(j.containsKey('spd'), isFalse);
      expect(j.containsKey('cog'), isFalse);
      final g = PositionFix.fromJson(j);
      expect(g.speedMps, isNull);
      expect(g.courseDeg, isNull);
      expect(g.source, FixSource.device);
      expect(g.position, const LatLng(43, 16));
    });

    test('missing source defaults to device', () {
      final g = PositionFix.fromJson(
          {'lat': 1, 'lon': 2, 'acc': 3, 't': t.millisecondsSinceEpoch});
      expect(g.source, FixSource.device);
    });
  });

  group('AlarmProfile', () {
    test('round trip of every built-in and a custom profile', () {
      final custom = AlarmProfile.builtIns[2].copyWith(
        id: 'c1',
        name: 'Custom',
        builtIn: false,
        warningRatio: 0.65,
        alarmDelaySec: 7,
        averagingSec: 0,
        gpsLostSec: 45,
        poorAccuracyM: 18.5,
        learnSwing: true,
        lowBatteryWarnPct: 40,
        lowBatteryAlarmPct: 25,
        snoozeSec: 60,
        vibrate: false,
        sound: 'bell',
      );
      for (final p in [...AlarmProfile.builtIns, custom]) {
        final q = AlarmProfile.fromJson(viaJson(p.toJson()));
        expect(q.toJson(), p.toJson());
      }
    });

    test('fromJson tolerates missing optional keys', () {
      final p = AlarmProfile.fromJson({'id': 'x', 'name': 'X'});
      const d = AlarmProfile(id: 'x', name: 'X');
      expect(p.toJson(), d.toJson());
    });

    test('fromJson tolerates integer-valued doubles for double fields', () {
      final p = AlarmProfile.fromJson(
          {'id': 'x', 'name': 'X', 'warningRatio': 1, 'poorAccuracyM': 30});
      expect(p.warningRatio, 1.0);
      expect(p.poorAccuracyM, 30.0);
    });

    test('copyWith with no arguments is identical', () {
      final p = AlarmProfile.builtIns[0];
      expect(p.copyWith().toJson(), p.toJson());
    });
  });

  group('BoatSettings', () {
    test('round trip', () {
      const b = BoatSettings(
          lengthM: 9.5, gpsToBowM: 3, gpsMarginM: 7, lastRodeM: 40, lastDepthM: 8.2);
      expect(BoatSettings.fromJson(viaJson(b.toJson())).toJson(), b.toJson());
    });
    test('missing keys use defaults', () {
      expect(BoatSettings.fromJson({}).toJson(), const BoatSettings().toJson());
    });
  });

  group('AlertEvent', () {
    test('round trip with and without optional fields', () {
      for (final e in [
        AlertEvent(reason: AlertReason.drag, time: t, distanceM: 47.25, acknowledgedAt: t.add(const Duration(minutes: 1))),
        AlertEvent(reason: AlertReason.gpsLost, time: t),
      ]) {
        final g = AlertEvent.fromJson(viaJson(e.toJson()));
        expect(g.reason, e.reason);
        expect(g.time, e.time);
        expect(g.distanceM, e.distanceM);
        expect(g.acknowledgedAt, e.acknowledgedAt);
      }
    });

    test('every reason survives', () {
      for (final r in AlertReason.values) {
        expect(AlertEvent.fromJson(viaJson(AlertEvent(reason: r, time: t).toJson())).reason, r);
      }
    });

    test('isAlarm severity', () {
      expect(AlertReason.values.where((r) => r.isAlarm).toSet(),
          {AlertReason.drag, AlertReason.gpsLost, AlertReason.criticalBattery});
    });
  });

  group('AnchorSession', () {
    AnchorSession full() => AnchorSession(
          id: 'abc',
          anchor: const LatLng(43.1633, 16.3972),
          radiusM: 52.5,
          initialRadiusM: 45,
          profile: AlarmProfile.builtIns[1],
          startedAt: t,
          endedAt: t.add(const Duration(hours: 9)),
          rodeM: 35,
          depthM: 6.5,
          maxDistanceM: 41.2,
          alerts: [
            AlertEvent(reason: AlertReason.nearEdge, time: t.add(const Duration(hours: 1))),
            AlertEvent(
                reason: AlertReason.drag,
                time: t.add(const Duration(hours: 2)),
                distanceM: 55,
                acknowledgedAt: t.add(const Duration(hours: 2, minutes: 1))),
          ],
          notes: 'Wind veered NW at 3am\n"quoted"',
          name: 'Palmižana',
        );

    void expectSame(AnchorSession a, AnchorSession b) =>
        expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));

    test('round trip with everything set', () {
      final s = full();
      final g = AnchorSession.fromJson(viaJson(s.toJson()));
      expectSame(g, s);
      expect(g.alerts, hasLength(2));
      expect(g.alerts[1].acknowledgedAt, s.alerts[1].acknowledgedAt);
      expect(g.endedAt, s.endedAt);
      expect(g.isActive, isFalse);
      expect(g.name, 'Palmižana');
      expect(g.profile.id, AlarmProfile.overnightId);
    });

    test('round trip with nulls (active session)', () {
      final s = AnchorSession(
        id: 'a',
        anchor: const LatLng(-16.8, 179.99),
        radiusM: 30,
        initialRadiusM: 30,
        profile: AlarmProfile.builtIns[0],
        startedAt: t,
      );
      final j = viaJson(s.toJson());
      for (final k in ['endedAt', 'rodeM', 'depthM', 'name']) {
        expect(j.containsKey(k), isFalse, reason: k);
      }
      final g = AnchorSession.fromJson(j);
      expectSame(g, s);
      expect(g.isActive, isTrue);
      expect(g.endedAt, isNull);
      expect(g.rodeM, isNull);
      expect(g.depthM, isNull);
      expect(g.name, isNull);
      expect(g.alerts, isEmpty);
      expect(g.notes, '');
    });

    test('fromJson tolerates missing optional keys', () {
      final g = AnchorSession.fromJson({
        'id': 'a',
        'lat': 43,
        'lon': 16,
        'radiusM': 40,
        'profile': {'id': 'p', 'name': 'P'},
        'startedAt': t.millisecondsSinceEpoch,
      });
      expect(g.initialRadiusM, 40);
      expect(g.maxDistanceM, 0);
      expect(g.alerts, isEmpty);
      expect(g.notes, '');
    });

    test('derived values', () {
      final s = full();
      expect(s.warningRadiusM, closeTo(52.5 * 0.8, 1e-9));
      expect(s.duration(t), const Duration(hours: 9));
      final active = s.copyWith(radiusM: 10);
      expect(active.radiusM, 10);
      expect(active.id, s.id);
      expect(active.startedAt, s.startedAt);
    });
  });

  group('TrackPoint', () {
    test('round trip', () {
      final p = TrackPoint(const LatLng(43.1633, 16.3972), t, 3.5);
      final g = TrackPoint.fromJson(viaJson(p.toJson()));
      expect(g.position, p.position);
      expect(g.time, t);
      expect(g.accuracyM, 3.5);
    });
  });
}
