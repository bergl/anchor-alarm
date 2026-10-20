import 'dart:async';
import 'dart:math' as math;

import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/services/location/location_source.dart';
import 'package:anchor_alarm/services/location/simulated_location_source.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<PositionFix>> collect(SimulatedLocationSource sim, int n,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final out = <PositionFix>[];
  final done = Completer<void>();
  final sub = sim.watch().listen((f) {
    out.add(f);
    if (out.length >= n && !done.isCompleted) done.complete();
  });
  await done.future.timeout(timeout, onTimeout: () {});
  await sub.cancel();
  return out;
}

void main() {
  const fast = Duration(milliseconds: 1);

  test('defaults and permission', () async {
    final sim = SimulatedLocationSource();
    expect(sim.anchor, SimulatedLocationSource.defaultAnchor);
    expect(sim.scenario, SimScenario.swing);
    expect(await sim.requestPermission(background: true), LocationPermissionResult.always);
    expect(await sim.available, isTrue);
    expect(sim.label, 'Simulator');
  });

  test('swing: noise-free boat lies at rode ± 2 m, downwind ± 25°', () {
    final sim = SimulatedLocationSource(rodeM: 25, windFromDeg: 0);
    final t = DateTime(2026, 10, 20, 22);
    for (var s = 0; s < 3600; s += 7) {
      final b = sim.boatAt(t.add(Duration(seconds: s)));
      final d = distanceM(sim.anchor, b);
      expect(d, inInclusiveRange(23 - 1e-6, 27 + 1e-6));
      final brg = bearingDeg(sim.anchor, b);
      final off = ((brg - 180 + 540) % 360) - 180;
      expect(off.abs(), lessThanOrEqualTo(25 + 1e-6));
    }
  });

  test('swing: emitted fixes stay within rode + 10 m with good accuracy', () async {
    final sim = SimulatedLocationSource(
        rodeM: 30, interval: fast, random: math.Random(7));
    final fixes = await collect(sim, 400);
    expect(fixes.length, greaterThanOrEqualTo(400));
    for (final f in fixes) {
      expect(distanceM(sim.anchor, f.position), lessThanOrEqualTo(30 + 10));
      expect(f.accuracyM, inInclusiveRange(3, 6));
      expect(f.source, FixSource.simulated);
    }
  });

  test('drag: boat moves away from the anchor over time', () {
    final sim = SimulatedLocationSource(rodeM: 25, windFromDeg: 90);
    sim.scenario = SimScenario.drag;
    final now = DateTime.now();
    final d0 = distanceM(sim.anchor, sim.boatAt(now));
    final d5 = distanceM(sim.anchor, sim.boatAt(now.add(const Duration(minutes: 5))));
    final d10 = distanceM(sim.anchor, sim.boatAt(now.add(const Duration(minutes: 10))));
    expect(d0, lessThan(30));
    // 0.4 m/s downwind: about 120 m and 240 m (± swing).
    expect(d5, closeTo(25 + 120, 15));
    expect(d10, closeTo(25 + 240, 15));
  });

  test('drag: times before the drag started do not pull the boat upwind', () {
    final sim = SimulatedLocationSource(rodeM: 25);
    final before = DateTime.now().subtract(const Duration(minutes: 10));
    final swingPos = sim.boatAt(before);
    sim.scenario = SimScenario.drag;
    expect(distanceM(sim.boatAt(before), swingPos), lessThan(0.01));
  });

  test('switching back from drag returns to swing', () {
    final sim = SimulatedLocationSource(rodeM: 25);
    sim.scenario = SimScenario.drag;
    sim.scenario = SimScenario.swing;
    final later = DateTime.now().add(const Duration(hours: 1));
    expect(distanceM(sim.anchor, sim.boatAt(later)), lessThanOrEqualTo(27.001));
  });

  test('relocate moves the anchor and the boat', () {
    final sim = SimulatedLocationSource(rodeM: 25);
    final elsewhere = destination(sim.anchor, 45, 10000);
    sim.relocate(elsewhere);
    expect(sim.anchor, elsewhere);
    expect(distanceM(elsewhere, sim.boatAt(DateTime.now())), lessThanOrEqualTo(27.001));
  });

  test('gpsLoss emits nothing', () async {
    final sim = SimulatedLocationSource(interval: fast);
    sim.scenario = SimScenario.gpsLoss;
    final fixes = await collect(sim, 1, timeout: const Duration(milliseconds: 200));
    expect(fixes, isEmpty);
  });

  test('poorGps reports 35–50 m accuracy', () async {
    final sim = SimulatedLocationSource(interval: fast, random: math.Random(3));
    sim.scenario = SimScenario.poorGps;
    final fixes = await collect(sim, 100);
    expect(fixes, isNotEmpty);
    for (final f in fixes) {
      expect(f.accuracyM, inInclusiveRange(35, 50));
    }
  });

  test('glitches: occasional jumps of 30–60 m, otherwise normal', () async {
    final sim = SimulatedLocationSource(
        rodeM: 25, interval: fast, random: math.Random(11));
    sim.scenario = SimScenario.glitches;
    final fixes = await collect(sim, 1000);
    final far = fixes.where((f) => distanceM(sim.anchor, f.position) > 40).length;
    expect(far, greaterThan(0));
    expect(far, lessThan(fixes.length * 0.1));
    for (final f in fixes) {
      expect(distanceM(sim.anchor, f.position), lessThan(25 + 2 + 20 + 60));
    }
  });

  test('currentFix returns a fix', () async {
    final sim = SimulatedLocationSource();
    expect(await sim.currentFix(), isNotNull);
  });

  test('heading is the bow direction, into the wind', () async {
    final sim = SimulatedLocationSource(windFromDeg: 0, interval: fast);
    await collect(sim, 3);
    final h = await sim.heading.first;
    expect(h, isNotNull);
    final off = ((h! + 540) % 360) - 180;
    expect(off.abs(), lessThanOrEqualTo(25 + 1e-6));
  });
}
