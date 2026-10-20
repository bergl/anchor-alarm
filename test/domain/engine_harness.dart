import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/watch_engine.dart';
import 'package:latlong2/latlong.dart';

const anchor = LatLng(43.16330, 16.39720);
final t0 = DateTime(2026, 10, 20, 22);

/// Overnight-like profile without learn swing, so the radius stays put.
final testProfile = AlarmProfile.builtIns[1].copyWith(learnSwing: false);

AlarmProfile builtIn(String id) =>
    AlarmProfile.builtIns.firstWhere((p) => p.id == id);

DateTime at(num sec) => t0.add(Duration(milliseconds: (sec * 1000).round()));

/// A fix [d] metres from [from] (default: the anchor) on bearing [b].
PositionFix fixAt(num sec, double d,
        {double b = 90, double acc = 4, LatLng from = anchor}) =>
    PositionFix(position: destination(from, b, d), accuracyM: acc, time: at(sec));

AnchorSession makeSession(AlarmProfile p,
        {double radius = 40, DateTime? startedAt, LatLng a = anchor}) =>
    AnchorSession(
      id: 's1',
      anchor: a,
      radiusM: radius,
      initialRadiusM: radius,
      profile: p,
      startedAt: startedAt ?? t0,
      rodeM: 30,
      depthM: 5,
    );

/// Drives an engine and records every snapshot and event.
class Harness {
  Harness(AlarmProfile p, {double radius = 40, DateTime? startedAt, num startSec = 0})
      : engine = AnchorWatchEngine(
            session: makeSession(p, radius: radius, startedAt: startedAt),
            now: at(startSec));

  final AnchorWatchEngine engine;
  final List<WatchSnapshot> snaps = [];
  final List<AlertEvent> events = [];

  WatchSnapshot get last => snaps.last;

  WatchSnapshot _rec(WatchSnapshot s) {
    snaps.add(s);
    events.addAll(s.events);
    return s;
  }

  WatchSnapshot fix(num sec, double d, {double b = 90, double acc = 4}) =>
      _rec(engine.onFix(fixAt(sec, d, b: b, acc: acc)));

  WatchSnapshot rawFix(PositionFix f) => _rec(engine.onFix(f));

  WatchSnapshot tick(num sec) => _rec(engine.onTick(at(sec)));

  WatchSnapshot ack(num sec) => _rec(engine.acknowledge(at(sec)));

  WatchSnapshot battery(num sec, int pct, {bool charging = false}) =>
      _rec(engine.onBattery(levelPct: pct, charging: charging, now: at(sec)));

  /// One fix per second for [from]..[to] inclusive, each followed by a tick
  /// half a second later. Returns the first snapshot index of this run.
  int run(int from, int to, double Function(int s) d,
      {double b = 90, double acc = 4, bool ticks = true}) {
    final start = snaps.length;
    for (var s = from; s <= to; s++) {
      fix(s, d(s), b: b, acc: acc);
      if (ticks) tick(s + 0.5);
    }
    return start;
  }

  /// Ticks only (no fixes), every [step] seconds.
  void ticks(num from, num to, {num step = 1}) {
    for (var s = from; s <= to; s += step) {
      tick(s);
    }
  }

  List<AlertEvent> eventsOf(AlertReason r) =>
      events.where((e) => e.reason == r).toList();

  bool get everRang => snaps.any((s) => s.ringing);

  /// Time (seconds from t0) of the first snapshot satisfying [test], or null.
  double? firstTime(bool Function(WatchSnapshot) test) {
    for (final s in snaps) {
      if (test(s)) return s.time.difference(t0).inMilliseconds / 1000;
    }
    return null;
  }
}
