import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/track_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_harness.dart';

void main() {
  PositionFix f(num sec, double d, {double acc = 4}) => fixAt(sec, d, acc: acc);

  test('first usable fix is always kept', () {
    final r = TrackRecorder();
    final p = r.offer(f(0, 20))!;
    expect(p.time, at(0));
    expect(p.accuracyM, 4);
    expect(distanceM(p.position, destination(anchor, 90, 20)), lessThan(1e-6));
  });

  test('fixes worse than 100 m are never kept and do not reset the clock', () {
    final r = TrackRecorder();
    expect(r.offer(f(0, 20, acc: 150)), isNull);
    expect(r.offer(f(1, 20)), isNotNull);
    expect(r.offer(f(40, 80, acc: 101)), isNull);
    expect(r.offer(f(41, 20)), isNotNull, reason: '40 s since last kept point');
  });

  test('never more often than minInterval, even when moving fast', () {
    final r = TrackRecorder();
    r.offer(f(0, 0));
    expect(r.offer(f(1, 50)), isNull);
    expect(r.offer(f(4.9, 100)), isNull);
    expect(r.offer(f(5, 100)), isNotNull);
  });

  test('between min and max interval only when moved at least minMoveM', () {
    final r = TrackRecorder();
    r.offer(f(0, 20));
    expect(r.offer(f(6, 22)), isNull); // 2 m
    expect(r.offer(f(7, 23.1)), isNotNull); // 3.1 m
    expect(r.offer(f(13, 23.1)), isNull);
  });

  test('at maxInterval kept without movement', () {
    final r = TrackRecorder();
    r.offer(f(0, 20));
    expect(r.offer(f(29, 20)), isNull);
    expect(r.offer(f(30, 20)), isNotNull);
  });

  test('during an alarm every fix after minInterval is kept', () {
    final r = TrackRecorder();
    r.offer(f(0, 20));
    expect(r.offer(f(3, 20), alarm: true), isNull);
    expect(r.offer(f(5, 20), alarm: true), isNotNull);
    expect(r.offer(f(10, 20), alarm: true), isNotNull);
  });

  test('slow drift accumulates from the last kept point, not the last fix', () {
    final r = TrackRecorder();
    var kept = 0;
    for (var s = 0; s <= 60; s++) {
      if (r.offer(f(s, 20 + 0.55 * s)) != null) kept++;
    }
    // 0.55 m/s: 3 m first exceeded after 6 s -> 0, 6, 12, ..., 60.
    expect(kept, 11);
  });

  test('an 8 h stationary night at 1 Hz stores about one point per 30 s', () {
    final r = TrackRecorder();
    var kept = 0;
    for (var s = 0; s < 8 * 3600; s++) {
      if (r.offer(f(s, 25 + (s % 3) * 0.5)) != null) kept++;
    }
    expect(kept, 960);
  });

  test('custom parameters', () {
    final r = TrackRecorder(
        minInterval: const Duration(seconds: 1),
        maxInterval: const Duration(seconds: 2),
        minMoveM: 100);
    r.offer(f(0, 0));
    expect(r.offer(f(1, 0)), isNull);
    expect(r.offer(f(2, 0)), isNotNull);
  });
}
