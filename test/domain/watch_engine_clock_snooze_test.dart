import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_harness.dart';

void main() {
  group('clock handling', () {
    test('stale cached fixes do not reset the GPS-lost timer', () {
      final h = Harness(testProfile);
      h.fix(0, 20);
      // From now on only a cached fix (timestamp t=0) keeps arriving.
      final cached = PositionFix(
          position: destination(anchor, 90, 20), accuracyM: 4, time: at(0));
      for (var s = 1; s <= 70; s++) {
        h.engine.onFix(cached, receivedAt: at(s));
        h.tick(s + 0.5);
      }
      expect(h.last.reasons, contains(AlertReason.gpsLost));
    });

    test('fresh fixes with receivedAt keep the watch alive', () {
      final h = Harness(testProfile);
      for (var s = 0; s <= 120; s++) {
        h.engine.onFix(fixAt(s, 20), receivedAt: at(s + 0.3));
        h.tick(s + 0.5);
      }
      expect(h.everRang, isFalse);
    });
  });

  group('snooze', () {
    test('leaving the ring again during a snooze rings immediately', () {
      final h = Harness(testProfile);
      h.run(0, 5, (_) => 20);
      h.run(6, 40, (_) => 60); // drag
      expect(h.last.ringing, isTrue);
      h.ack(40.7);
      expect(h.last.ringing, isFalse);
      // Swings back inside, then out again well before the 2 min snooze ends.
      h.run(41, 70, (_) => 20);
      expect(h.last.ringing, isFalse);
      h.run(71, 100, (_) => 60);
      final rang = h.firstTime((s) => s.time.isAfter(at(71)) && s.ringing);
      expect(rang, isNotNull);
      expect(rang, lessThan(100));
      expect(h.eventsOf(AlertReason.drag), hasLength(2));
    });
  });
}
