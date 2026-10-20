import 'dart:math' as math;

import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/watch_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_harness.dart';

void main() {
  group('basic states', () {
    test('boat staying inside is safe for an hour, no events', () {
      final h = Harness(testProfile);
      final rnd = math.Random(1);
      h.run(0, 3600, (_) => 25 + rnd.nextDouble() * 5,
          acc: 5); // swings 25..30 m, radius 40, warning 36
      expect(h.snaps.every((s) => s.state == WatchState.safe), isTrue);
      expect(h.events, isEmpty);
      expect(h.everRang, isFalse);
      expect(h.last.distanceM, inInclusiveRange(25, 30));
      expect(h.last.radiusM, 40);
      expect(h.last.warningRadiusM, closeTo(36, 1e-9));
      expect(h.last.maxDistanceM, lessThanOrEqualTo(30));
      expect(h.engine.session.alerts, isEmpty);
    });

    test('snapshot reports bearing from the anchor and position', () {
      final h = Harness(testProfile);
      h.fix(0, 20, b: 135);
      expect(h.last.bearingFromAnchorDeg, closeTo(135, 0.01));
      expect(h.last.distanceM, closeTo(20, 0.01));
      expect(h.last.hasFix, isTrue);
      expect(h.last.lastFix, isNotNull);
    });

    test('before any fix: no position, safe', () {
      final h = Harness(testProfile);
      h.tick(1);
      expect(h.last.hasFix, isFalse);
      expect(h.last.distanceM, isNull);
      expect(h.last.state, WatchState.safe);
    });
  });

  group('warning ring', () {
    final noAvg = testProfile.copyWith(averagingSec: 0);

    test('outside warning ring for less than the delay: no warning', () {
      final h = Harness(noAvg);
      h.run(0, 59, (_) => 20);
      h.run(60, 68, (_) => 38); // 9 fixes, last tick at 68.5 < 60 + 10
      h.run(69, 120, (_) => 20);
      expect(h.events, isEmpty);
      expect(h.snaps.every((s) => s.state == WatchState.safe), isTrue);
    });

    test('outside warning ring for the delay: warning and exactly one event', () {
      final h = Harness(noAvg);
      h.run(0, 59, (_) => 20);
      h.run(60, 120, (_) => 38);
      expect(h.firstTime((s) => s.state == WatchState.warning), 70);
      expect(h.last.state, WatchState.warning);
      expect(h.last.reasons, {AlertReason.nearEdge});
      expect(h.last.ringing, isFalse);
      expect(h.last.outsideSince, at(60));
      expect(h.eventsOf(AlertReason.nearEdge), hasLength(1));
      expect(h.events, hasLength(1));
      // Warnings are not latched.
      h.run(121, 130, (_) => 20);
      expect(h.last.state, WatchState.safe);
      expect(h.last.outsideSince, isNull);
    });

    test('with averaging, a sustained excursion still warns once', () {
      final h = Harness(testProfile);
      h.run(0, 59, (_) => 20);
      h.run(60, 180, (_) => 38);
      expect(h.last.state, WatchState.warning);
      expect(h.eventsOf(AlertReason.nearEdge), hasLength(1));
    });
  });

  group('drag alarm', () {
    test('outside alarm ring for the delay: alarm, ringing, one event', () {
      final h = Harness(testProfile);
      h.run(0, 59, (_) => 20);
      h.run(60, 240, (_) => 50);
      final alarmAt = h.firstTime((s) => s.state == WatchState.alarm)!;
      // Averaging (10 s window) crosses 40 m after ~6 fixes, then 10 s delay.
      expect(alarmAt, greaterThanOrEqualTo(70));
      expect(alarmAt, lessThanOrEqualTo(60 + 10 + 10 + 1));
      expect(h.last.ringing, isTrue);
      expect(h.last.reasons, contains(AlertReason.drag));
      expect(h.last.reasons, isNot(contains(AlertReason.nearEdge)));
      expect(h.eventsOf(AlertReason.drag), hasLength(1));
      expect(h.engine.session.alerts.where((a) => a.reason == AlertReason.drag),
          hasLength(1));
      expect(h.eventsOf(AlertReason.drag).single.distanceM, greaterThan(40));
      // Once raised, never more than one event per snapshot step for drag.
      for (final s in h.snaps) {
        expect(s.events.where((e) => e.reason == AlertReason.drag).length,
            lessThanOrEqualTo(1));
      }
      expect(h.last.maxDistanceM, closeTo(50, 0.01));
    });

    test('alarm is not raised before the delay has elapsed', () {
      final h = Harness(testProfile.copyWith(averagingSec: 0));
      h.run(0, 9, (_) => 20);
      h.fix(10, 50);
      h.tick(19.9);
      expect(h.last.state, isNot(WatchState.alarm));
      h.tick(20);
      expect(h.last.state, WatchState.alarm);
      expect(h.last.ringing, isTrue);
    });

    test('short excursion beyond the ring (shorter than delay) does not alarm', () {
      final h = Harness(testProfile.copyWith(averagingSec: 0));
      h.run(0, 30, (_) => 20);
      h.run(31, 38, (_) => 50);
      h.run(39, 100, (_) => 20);
      expect(h.everRang, isFalse);
      expect(h.eventsOf(AlertReason.drag), isEmpty);
    });

    test('alarm latches when the boat returns inside', () {
      final h = Harness(testProfile);
      h.run(0, 59, (_) => 20);
      h.run(60, 120, (_) => 50);
      h.run(121, 600, (_) => 20);
      expect(h.last.state, WatchState.alarm);
      expect(h.last.ringing, isTrue);
      expect(h.last.reasons, contains(AlertReason.drag));
      expect(h.eventsOf(AlertReason.drag), hasLength(1));
    });

    test('acknowledge after the boat is back inside clears the alarm', () {
      final h = Harness(testProfile);
      h.run(0, 59, (_) => 20);
      h.run(60, 120, (_) => 50);
      h.run(121, 200, (_) => 20);
      final s = h.ack(200.7);
      expect(s.state, WatchState.safe);
      expect(s.ringing, isFalse);
      expect(s.snoozedUntil, isNull);
      expect(s.reasons, isEmpty);
      final drag = h.engine.session.alerts
          .where((a) => a.reason == AlertReason.drag)
          .single;
      expect(drag.acknowledgedAt, at(200.7));
      h.run(201, 1000, (_) => 20);
      expect(h.everRangAfter(200.7), isFalse);
      expect(h.eventsOf(AlertReason.drag), hasLength(1));
    });

    test('acknowledge while still outside snoozes, then rings again with a new event', () {
      final p = testProfile;
      final h = Harness(p);
      h.run(0, 59, (_) => 20);
      h.run(60, 100, (_) => 50);
      expect(h.last.ringing, isTrue);
      final s = h.ack(100.7);
      expect(s.ringing, isFalse);
      expect(s.state, WatchState.alarm);
      expect(s.snoozedUntil, at(100.7 + p.snoozeSec));
      expect(s.events, isEmpty);
      h.run(101, 100 + p.snoozeSec - 1, (_) => 50);
      expect(h.everRangAfter(100.7), isFalse);
      expect(h.eventsOf(AlertReason.drag), hasLength(1));
      h.tick(100.7 + p.snoozeSec);
      expect(h.last.ringing, isTrue);
      expect(h.last.snoozedUntil, isNull);
      expect(h.last.events.map((e) => e.reason), [AlertReason.drag]);
      h.run(221, 300, (_) => 50);
      expect(h.eventsOf(AlertReason.drag), hasLength(2));
      expect(h.last.ringing, isTrue);
    });

    test('snooze that expires after the boat came back drops the alarm', () {
      final h = Harness(testProfile);
      h.run(0, 59, (_) => 20);
      h.run(60, 100, (_) => 50);
      h.ack(100.5);
      h.run(101, 300, (_) => 20);
      expect(h.last.state, WatchState.safe);
      expect(h.everRangAfter(100.5), isFalse);
      expect(h.eventsOf(AlertReason.drag), hasLength(1));
    });

    test('a new alarm reason during snooze rings immediately', () {
      final h = Harness(testProfile);
      h.run(0, 59, (_) => 20);
      h.run(60, 100, (_) => 50);
      h.ack(100.5);
      expect(h.last.ringing, isFalse);
      h.fix(101, 50);
      final s = h.battery(101.2, 5);
      expect(s.ringing, isTrue);
      expect(s.snoozedUntil, isNull);
      expect(s.events.map((e) => e.reason), [AlertReason.criticalBattery]);
      expect(s.reasons, containsAll([AlertReason.drag, AlertReason.criticalBattery]));
    });

    test('acknowledge with nothing latched is harmless', () {
      final h = Harness(testProfile);
      h.run(0, 10, (_) => 20);
      final s = h.ack(11);
      expect(s.state, WatchState.safe);
      expect(s.snoozedUntil, isNull);
      expect(s.ringing, isFalse);
    });

    test('engine session exposes max distance', () {
      final h = Harness(testProfile.copyWith(averagingSec: 0));
      h.run(0, 10, (s) => 20.0 + s);
      h.run(11, 20, (_) => 10);
      expect(h.engine.session.maxDistanceM, closeTo(30, 0.01));
      expect(h.last.maxDistanceM, closeTo(30, 0.01));
    });
  });

  group('GPS glitches', () {
    for (final p in AlarmProfile.builtIns) {
      for (final spikeFromBoat in [true, false]) {
        test('${p.name}: single 60 m spike '
            '(${spikeFromBoat ? 'beyond the boat' : 'from the anchor'}) '
            'with good reported accuracy does not alarm', () {
          // Boat lies at 90 % of the radius, i.e. past the warning ring but
          // inside the alarm ring: the worst place for a spike.
          final h = Harness(p.copyWith(learnSwing: false), radius: 40);
          h.run(0, 120, (_) => 36);
          final spike = spikeFromBoat ? 36.0 + 60 : 60.0;
          h.fix(121, spike, acc: 3);
          h.tick(121.5);
          h.run(122, 300, (_) => 36);
          expect(h.eventsOf(AlertReason.drag), isEmpty);
          expect(h.everRang, isFalse);
        });
      }
    }

    test('spike reporting poor accuracy is down-weighted', () {
      final h = Harness(testProfile);
      h.run(0, 60, (_) => 30);
      h.fix(61, 200, acc: 60);
      expect(h.last.distanceM, lessThan(32));
    });

    test('two consecutive spikes do not alarm either', () {
      final h = Harness(testProfile);
      h.run(0, 60, (_) => 30);
      h.run(61, 62, (_) => 100, acc: 3);
      h.run(63, 200, (_) => 30);
      expect(h.everRang, isFalse);
    });

    test('a real jump that persists is still detected', () {
      final h = Harness(testProfile);
      h.run(0, 60, (_) => 30);
      h.run(61, 120, (_) => 90, acc: 3);
      expect(h.last.state, WatchState.alarm);
      expect(h.firstTime((s) => s.ringing)!, lessThanOrEqualTo(61 + 10 + 10 + 1));
    });

    test('fixes worse than 100 m are ignored for the distance decision', () {
      final h = Harness(testProfile);
      h.run(0, 60, (_) => 20);
      final dBefore = h.last.distanceM;
      h.run(61, 110, (_) => 500, acc: 150); // 50 s < gpsLostSec 60
      expect(h.last.distanceM, dBefore);
      expect(h.eventsOf(AlertReason.drag), isEmpty);
      expect(h.everRang, isFalse);
      expect(h.last.lastFix!.accuracyM, 150);
    });

    test('only unusable fixes for gpsLostSec raises GPS lost', () {
      final h = Harness(testProfile);
      h.run(0, 60, (_) => 20);
      h.run(61, 130, (_) => 20, acc: 150);
      expect(h.firstTime((s) => s.reasons.contains(AlertReason.gpsLost)), 120);
      expect(h.eventsOf(AlertReason.gpsLost), hasLength(1));
      expect(h.last.ringing, isTrue);
      expect(h.eventsOf(AlertReason.drag), isEmpty);
    });
  });

  group('GPS lost', () {
    test('engine that never received a fix alarms after gpsLostSec of ticks', () {
      final h = Harness(testProfile, startSec: 0);
      h.ticks(1, 59);
      expect(h.everRang, isFalse);
      h.tick(60);
      expect(h.last.state, WatchState.alarm);
      expect(h.last.ringing, isTrue);
      expect(h.last.reasons, {AlertReason.gpsLost});
      h.ticks(61, 200);
      expect(h.eventsOf(AlertReason.gpsLost), hasLength(1));
      expect(h.events, hasLength(1));
    });

    test('fixes stop: alarm after gpsLostSec, ticks only', () {
      final h = Harness(testProfile);
      h.run(0, 100, (_) => 20, ticks: false);
      h.ticks(100.5, 159.5);
      expect(h.everRang, isFalse);
      h.tick(160);
      expect(h.last.reasons, contains(AlertReason.gpsLost));
      expect(h.last.ringing, isTrue);
    });

    test('storm profile: GPS lost after 30 s', () {
      final h = Harness(builtIn(AlarmProfile.stormId));
      h.fix(0, 20);
      h.ticks(1, 29);
      expect(h.everRang, isFalse);
      h.tick(30);
      expect(h.last.reasons, contains(AlertReason.gpsLost));
    });

    test('GPS lost clears with the next fix but stays latched until acknowledged', () {
      final h = Harness(testProfile);
      h.fix(0, 20);
      h.ticks(1, 70);
      h.run(71, 90, (_) => 20);
      expect(h.last.state, WatchState.alarm);
      expect(h.last.ringing, isTrue);
      final s = h.ack(90.5);
      expect(s.state, WatchState.safe);
      expect(s.ringing, isFalse);
      h.run(91, 400, (_) => 20);
      expect(h.everRangAfter(90.5), isFalse);
    });

    test('acknowledging while GPS is still lost re-rings after snooze', () {
      final h = Harness(testProfile);
      h.fix(0, 20);
      h.ticks(1, 61);
      h.ack(61.5);
      h.ticks(62, 181);
      expect(h.everRangAfter(61.5), isFalse);
      h.tick(181.5);
      expect(h.last.ringing, isTrue);
      expect(h.eventsOf(AlertReason.gpsLost), hasLength(2));
    });

    test('stale position does not move the drag timer, nor clear it', () {
      final h = Harness(testProfile.copyWith(averagingSec: 0));
      h.run(0, 10, (_) => 20);
      h.fix(11, 50); // outside, then GPS goes silent
      h.ticks(12, 30);
      // Drag delay elapsed on the last known position: alarm (fail-safe).
      expect(h.last.reasons, contains(AlertReason.drag));
    });
  });

  group('poor GPS', () {
    test('accuracy worse than threshold for 2 min raises a warning once', () {
      final h = Harness(testProfile);
      h.run(0, 30, (_) => 20);
      h.run(31, 300, (_) => 20, acc: 40);
      // Averaged accuracy crosses the threshold a few seconds after the first
      // poor fix (10 s window), then the 2 min delay applies.
      expect(h.firstTime((s) => s.reasons.contains(AlertReason.gpsPoor)),
          inInclusiveRange(151, 161));
      expect(h.last.state, WatchState.warning);
      expect(h.last.ringing, isFalse);
      expect(h.eventsOf(AlertReason.gpsPoor), hasLength(1));
      h.run(301, 310, (_) => 20, acc: 5);
      expect(h.last.reasons, isNot(contains(AlertReason.gpsPoor)));
    });

    test('accuracy just below the threshold is fine', () {
      final h = Harness(testProfile);
      h.run(0, 400, (_) => 20, acc: 25);
      expect(h.events, isEmpty);
    });

    test('unusable (>100 m) fixes also count as poor before GPS lost', () {
      final h = Harness(testProfile.copyWith(gpsLostSec: 600));
      h.run(0, 10, (_) => 20);
      h.run(11, 200, (_) => 20, acc: 200);
      expect(h.last.reasons, contains(AlertReason.gpsPoor));
    });
  });

  group('battery', () {
    test('warning at the warn level, alarm at the critical level', () {
      final h = Harness(testProfile);
      h.fix(0, 20);
      expect(h.battery(1, 21).state, WatchState.safe);
      var s = h.battery(2, 20);
      expect(s.state, WatchState.warning);
      expect(s.reasons, {AlertReason.lowBattery});
      expect(s.events.single.reason, AlertReason.lowBattery);
      s = h.battery(3, 19);
      expect(s.events, isEmpty);
      s = h.battery(4, 10);
      expect(s.state, WatchState.alarm);
      expect(s.ringing, isTrue);
      expect(s.reasons, {AlertReason.criticalBattery});
      expect(s.events.single.reason, AlertReason.criticalBattery);
      expect(h.eventsOf(AlertReason.criticalBattery), hasLength(1));
    });

    test('charging suppresses battery alerts', () {
      final h = Harness(testProfile);
      h.fix(0, 20);
      final s = h.battery(1, 3, charging: true);
      expect(s.state, WatchState.safe);
      expect(s.events, isEmpty);
    });

    test('plugging in clears the condition; acknowledge then clears the latch', () {
      final h = Harness(testProfile);
      h.fix(0, 20);
      h.battery(1, 5);
      expect(h.last.ringing, isTrue);
      h.battery(2, 5, charging: true);
      expect(h.last.ringing, isTrue, reason: 'latched until acknowledged');
      expect(h.ack(3).state, WatchState.safe);
    });

    test('storm profile uses 30 % / 15 %', () {
      final h = Harness(builtIn(AlarmProfile.stormId));
      h.fix(0, 20);
      expect(h.battery(1, 30).reasons, {AlertReason.lowBattery});
      expect(h.battery(2, 15).reasons, {AlertReason.criticalBattery});
    });
  });

  group('learn swing (suggestion only)', () {
    final learn = testProfile.copyWith(learnSwing: true);

    test('suggests a wider radius within the first 15 minutes, never applies it', () {
      final h = Harness(learn);
      h.run(0, 60, (_) => 20);
      expect(h.last.swingSuggestionM, isNull);
      h.run(61, 120, (_) => 38);
      expect(h.last.radiusM, 40);
      expect(h.last.swingSuggestionM, (38 / learnSwingTrigger).ceilToDouble());
      expect(h.engine.session.radiusM, 40);
    });

    test('a steady drag in the first minutes still alarms (regression)', () {
      final h = Harness(learn, radius: 47);
      h.run(0, 60, (_) => 35);
      // Anchor drags at 0.4 m/s.
      h.run(61, 200, (s) => 35 + 0.4 * (s - 60));
      expect(h.last.radiusM, 47);
      expect(h.everRang, isTrue);
      expect(h.eventsOf(AlertReason.drag), hasLength(1));
    });

    test('suggestion is capped at 1.5x the initial radius', () {
      final h = Harness(learn);
      h.run(0, 60, (_) => 20);
      h.run(61, 70, (_) => 70);
      expect(h.last.swingSuggestionM, closeTo(60, 1e-9));
    });

    test('no suggestion after 15 minutes', () {
      final h = Harness(learn);
      h.run(0, 15 * 60, (_) => 20);
      h.run(15 * 60 + 1, 15 * 60 + 20, (_) => 38);
      expect(h.last.swingSuggestionM, isNull);
    });

    test('no suggestion with learnSwing off', () {
      final h = Harness(testProfile);
      h.run(0, 120, (_) => 39);
      expect(h.snaps.every((s) => s.swingSuggestionM == null), isTrue);
    });

    test('accepting the suggestion via updateSession clears it', () {
      final h = Harness(learn);
      h.run(0, 60, (_) => 38);
      final sug = h.last.swingSuggestionM!;
      h.engine.updateSession(h.engine.session.copyWith(radiusM: sug));
      h.run(61, 70, (_) => 38);
      expect(h.last.radiusM, sug);
      expect(h.last.swingSuggestionM, isNull);
    });

    test('no suggestion on poor accuracy', () {
      final h = Harness(learn);
      h.run(0, 120, (_) => 39, acc: 40);
      expect(h.last.radiusM, 40);
      expect(h.snaps.every((s) => s.swingSuggestionM == null), isTrue);
    });

    test('a watch resumed after a restart does not learn again', () {
      // Session started two hours ago; engine rebuilt now (app restart).
      final h = Harness(learn, startedAt: t0, startSec: 7200);
      h.run(7200, 7300, (_) => 45);
      expect(h.last.radiusM, 40);
      expect(h.last.state, WatchState.alarm);
    });
  });

  group('updateSession', () {
    test('moving the anchor recomputes distance and can raise the alarm', () {
      final h = Harness(testProfile);
      h.run(0, 60, (_) => 20, b: 0);
      final moved = destination(anchor, 180, 40); // boat now 60 m away
      h.engine.updateSession(h.engine.session.copyWith(anchor: moved));
      final s = h.tick(60.6);
      expect(s.distanceM, closeTo(60, 0.1));
      expect(s.maxDistanceM, closeTo(60, 0.1));
      expect(h.engine.session.anchor, moved);
      h.run(61, 100, (_) => 20, b: 0);
      expect(h.last.state, WatchState.alarm);
    });

    test('moving the anchor closer resets the excursion timer', () {
      final h = Harness(testProfile.copyWith(averagingSec: 0));
      h.run(0, 10, (_) => 20, b: 0);
      h.run(11, 15, (_) => 50, b: 0);
      final moved = destination(anchor, 0, 30); // boat 20 m from new anchor
      h.engine.updateSession(h.engine.session.copyWith(anchor: moved));
      h.tick(15.5);
      expect(h.last.distanceM, closeTo(20, 0.1));
      expect(h.last.maxDistanceM, closeTo(20, 0.1));
      h.run(16, 60, (_) => 50, b: 0);
      expect(h.everRang, isFalse);
    });

    test('changing radius keeps latched alarms', () {
      final h = Harness(testProfile);
      h.run(0, 100, (_) => 50);
      expect(h.last.ringing, isTrue);
      h.engine.updateSession(h.engine.session.copyWith(radiusM: 80));
      h.tick(100.6);
      expect(h.last.ringing, isTrue);
      expect(h.ack(101).state, WatchState.safe);
    });
  });

  group('configs', () {
    test('delay 0 and averaging 0: alarm on the first outside fix', () {
      final h = Harness(testProfile.copyWith(alarmDelaySec: 0, averagingSec: 0));
      h.run(0, 10, (_) => 20);
      final s = h.fix(11, 41);
      expect(s.state, WatchState.alarm);
      expect(s.ringing, isTrue);
      expect(s.events.map((e) => e.reason), [AlertReason.drag]);
    });

    test('averaging 0 uses the latest fix only', () {
      final h = Harness(testProfile.copyWith(averagingSec: 0));
      h.fix(0, 10);
      h.fix(1, 30);
      expect(h.last.distanceM, closeTo(30, 0.01));
      expect(h.last.accuracyM, 4);
    });

    test('averaging is accuracy weighted (1/acc^2)', () {
      final h = Harness(testProfile.copyWith(averagingSec: 60));
      h.fix(0, 10, acc: 2); // weight 1/4
      h.fix(1, 30, acc: 4); // weight 1/16
      expect(h.last.distanceM, closeTo((10 * 4 + 30 * 1) / 5, 0.01));
      expect(h.last.accuracyM, 3);
    });

    test('fixes older than the averaging window drop out', () {
      final h = Harness(testProfile.copyWith(averagingSec: 5));
      h.fix(0, 10);
      h.fix(20, 30);
      expect(h.last.distanceM, closeTo(30, 0.01));
    });
  });

  group('built-in profiles', () {
    test('match DESIGN.md', () {
      final l = builtIn(AlarmProfile.lunchId);
      final o = builtIn(AlarmProfile.overnightId);
      final s = builtIn(AlarmProfile.stormId);
      expect([l.warningRatio, o.warningRatio, s.warningRatio], [0.9, 0.9, 0.85]);
      expect([l.alarmDelaySec, o.alarmDelaySec, s.alarmDelaySec], [20, 10, 5]);
      expect([l.averagingSec, o.averagingSec, s.averagingSec], [15, 10, 5]);
      expect([l.gpsLostSec, o.gpsLostSec, s.gpsLostSec], [60, 60, 30]);
      expect([l.poorAccuracyM, o.poorAccuracyM, s.poorAccuracyM], [30, 25, 20]);
      expect([l.learnSwing, o.learnSwing, s.learnSwing], [true, true, false]);
      expect([l.lowBatteryWarnPct, o.lowBatteryWarnPct, s.lowBatteryWarnPct],
          [20, 20, 30]);
      expect([l.lowBatteryAlarmPct, o.lowBatteryAlarmPct, s.lowBatteryAlarmPct],
          [10, 10, 15]);
      expect(AlarmProfile.builtIns.every((p) => p.builtIn), isTrue);
    });

    for (final p in AlarmProfile.builtIns) {
      test('${p.name}: noisy swing for 8 h never alarms', () {
        final h = Harness(p);
        final rnd = math.Random(42);
        for (var s = 0; s <= 8 * 3600; s++) {
          final bearing = 90 + 25 * math.sin(2 * math.pi * s / 240);
          // Boat lies at ~25 m, ±2 m, plus GPS noise of a few metres.
          final d = 25 + 2 * math.sin(2 * math.pi * s / 37);
          final noisy = destination(destination(anchor, bearing, d),
              rnd.nextDouble() * 360, rnd.nextDouble() * 4);
          h.rawFix(PositionFix(position: noisy, accuracyM: 4, time: at(s)));
          if (s % 5 == 0) h.tick(s + 0.5);
        }
        expect(h.everRang, isFalse);
        expect(h.events.where((e) => e.reason.isAlarm), isEmpty);
        expect(h.last.radiusM, 40, reason: 'boat never got near the ring');
      });

      test('${p.name}: drag at 0.4 m/s after settling is detected promptly', () {
        final h = Harness(p);
        const settle = 20 * 60; // past the learn-swing period
        h.run(0, settle, (_) => 25, ticks: false);
        h.run(settle + 1, settle + 300, (s) => 25 + 0.4 * (s - settle));
        // True crossing of the 40 m ring at settle + 37.5 s.
        final rang = h.firstTime((s) => s.ringing)!;
        expect(rang, greaterThan(settle + 37.5));
        expect(rang - (settle + 37.5),
            lessThanOrEqualTo(p.averagingSec / 2 + p.alarmDelaySec + 2));
        expect(h.eventsOf(AlertReason.drag), hasLength(1));
      });

      test('${p.name}: chain parted, drifting at 3 m/s, glitch filter does not '
          'delay the alarm', () {
        final h = Harness(p);
        const settle = 20 * 60;
        h.run(0, settle, (_) => 25, ticks: false);
        h.run(settle + 1, settle + 120, (s) => 25 + 3.0 * (s - settle));
        // True crossing at settle + 5 s.
        final rang = h.firstTime((s) => s.ringing)!;
        expect(rang - (settle + 5),
            lessThanOrEqualTo(p.averagingSec / 2 + p.alarmDelaySec + 2));
      });
    }
  });
}

extension on Harness {
  bool everRangAfter(num sec) =>
      snaps.any((s) => s.time.isAfter(at(sec)) && s.ringing);
}
