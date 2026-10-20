import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'geo.dart';
import 'models.dart';

/// Fixes with accuracy worse than this are ignored for distance decisions
/// (they still count as "poor GPS" but not as a usable fix).
const double maxUsableAccuracyM = 100;

/// How long accuracy must stay poor before the poor-GPS warning is raised.
const Duration poorGpsDelay = Duration(minutes: 2);

/// Fixes farther than this (or 3x their own accuracy, if larger) from the
/// median of the averaging window are treated as glitches and not averaged.
const double outlierMinM = 20;

/// Learn-swing parameters (see DESIGN.md).
const Duration learnSwingPeriod = Duration(minutes: 15);
const double learnSwingCap = 1.5;
const double learnSwingTrigger = 0.9;

/// Result of feeding the engine a fix, a clock tick or a user action.
class WatchSnapshot {
  const WatchSnapshot({
    required this.time,
    required this.state,
    required this.reasons,
    required this.ringing,
    required this.radiusM,
    required this.warningRadiusM,
    required this.maxDistanceM,
    this.distanceM,
    this.bearingFromAnchorDeg,
    this.position,
    this.accuracyM,
    this.lastFix,
    this.outsideSince,
    this.snoozedUntil,
    this.events = const [],
    this.radiusChanged = false,
  });

  final DateTime time;
  final WatchState state;

  /// All currently active warning and alarm reasons (including latched alarms).
  final Set<AlertReason> reasons;

  /// True while an alarm should be sounding (latched and not snoozed).
  final bool ringing;
  final double radiusM;
  final double warningRadiusM;
  final double maxDistanceM;

  /// Distance of the (averaged) boat position from the anchor.
  final double? distanceM;

  /// Bearing from the anchor to the boat.
  final double? bearingFromAnchorDeg;

  /// Averaged boat position used for decisions.
  final LatLng? position;

  /// Mean accuracy of the fixes in the averaging window.
  final double? accuracyM;
  final PositionFix? lastFix;

  /// When the boat first left the warning ring in the current excursion.
  final DateTime? outsideSince;
  final DateTime? snoozedUntil;

  /// Alerts newly raised by this step (rising edges), for the log and notifications.
  final List<AlertEvent> events;

  /// True when learn-swing widened the radius in this step.
  final bool radiusChanged;

  bool get hasFix => position != null;
}

/// Deterministic anchor watch logic. Feed it position fixes ([onFix]), clock
/// ticks ([onTick], about once a second) and battery readings ([onBattery]);
/// it returns a [WatchSnapshot] describing what the app should show and do.
///
/// It owns no timers and reads no clock, so it is fully unit-testable.
class AnchorWatchEngine {
  AnchorWatchEngine({
    required AnchorSession session,
    required DateTime now,
  })  : _session = session,
        // Learn swing runs during the first minutes of the *session*, not of
        // this engine instance (which is rebuilt when a watch is resumed).
        _startedAt = session.startedAt,
        _lastUsableFixAt = now,
        _maxDistanceM = session.maxDistanceM {
    _projection = LocalProjection(session.anchor);
  }

  AnchorSession _session;
  late LocalProjection _projection;
  final DateTime _startedAt;

  final List<PositionFix> _window = [];
  PositionFix? _lastFix;
  DateTime _lastUsableFixAt;
  LatLng? _position;
  double? _accuracyM;
  double? _distanceM;
  double _maxDistanceM;

  DateTime? _nearEdgeSince;
  DateTime? _outsideSince;
  DateTime? _poorSince;

  int? _batteryPct;
  bool _charging = true;

  /// Alarm reasons raised and not yet acknowledged (or still true after a snooze).
  final Set<AlertReason> _latched = {};

  /// Warning reasons active in the previous step, for rising-edge detection.
  Set<AlertReason> _prevWarnings = {};

  /// Alarm conditions true in the previous step.
  Set<AlertReason> _prevAlarms = {};
  DateTime? _snoozedUntil;

  AnchorSession get session => _session.copyWith(maxDistanceM: _maxDistanceM);
  AlarmProfile get _p => _session.profile;

  /// Replace anchor position, radius or profile (e.g. user dragged the anchor).
  /// Excursion timers restart; latched alarms stay until acknowledged.
  void updateSession(AnchorSession s) {
    final anchorMoved = s.anchor != _session.anchor;
    _session = s;
    if (anchorMoved) {
      _projection = LocalProjection(s.anchor);
      _maxDistanceM = 0;
    }
    _nearEdgeSince = null;
    _outsideSince = null;
    _recompute();
  }

  /// Feeds a position fix. [receivedAt] is the system time the fix arrived
  /// (defaults to the fix time). Timers such as GPS-lost run on the system
  /// clock, so a fix whose own timestamp is far behind (a stale cached fix) is
  /// not treated as a sign of a working GPS.
  WatchSnapshot onFix(PositionFix fix, {DateTime? receivedAt}) {
    _lastFix = fix;
    final now = receivedAt ?? fix.time;
    // A repeated or out-of-order fix carries no new information.
    final repeated = _window.isNotEmpty && !fix.time.isAfter(_window.last.time);
    final stale = repeated ||
        now.difference(fix.time) >= Duration(seconds: _p.gpsLostSec);

    if (fix.accuracyM <= maxUsableAccuracyM && !stale) {
      _lastUsableFixAt = now;
      _window.add(fix);
      _trimWindow(fix.time);
      _recompute();
    }
    return _evaluate(now);
  }

  WatchSnapshot onTick(DateTime now) => _evaluate(now);

  WatchSnapshot onBattery({
    required int levelPct,
    required bool charging,
    required DateTime now,
  }) {
    _batteryPct = levelPct;
    _charging = charging;
    return _evaluate(now);
  }

  /// User silenced the alarm. Alarms whose condition has cleared are dropped;
  /// those still true ring again after the profile's snooze time.
  WatchSnapshot acknowledge(DateTime now) {
    final active = _activeAlarmConditions(now);
    _latched.retainAll(active);
    _snoozedUntil =
        _latched.isEmpty ? null : now.add(Duration(seconds: _p.snoozeSec));
    _session = _session.copyWith(alerts: [
      for (final a in _session.alerts)
        a.acknowledgedAt == null && a.reason.isAlarm
            ? a.copyWith(acknowledgedAt: now)
            : a,
    ]);
    return _evaluate(now);
  }

  void _trimWindow(DateTime now) {
    final keep = Duration(seconds: _p.averagingSec);
    if (_p.averagingSec <= 0) {
      if (_window.length > 1) _window.removeRange(0, _window.length - 1);
      return;
    }
    _window.removeWhere((f) => now.difference(f.time) > keep);
    if (_window.isEmpty && _lastFix != null) _window.add(_lastFix!);
  }

  /// Accuracy-weighted mean of the window, in a local projection around the anchor.
  void _recompute() {
    if (_window.isEmpty) return;
    final xy = [for (final f in _window) _projection.toXY(f.position)];
    // Outlier rejection: a single GPS jump that still reports good accuracy
    // would otherwise drag the mean outside the ring for the whole averaging
    // window, which is as long as the alarm delay. With 3+ fixes, ignore those
    // far from the per-axis median (a real drag moves the median too).
    final keep = List.filled(_window.length, true);
    if (_window.length >= 3) {
      double median(List<double> v) {
        v.sort();
        final n = v.length;
        return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
      }

      final mx = median([for (final p in xy) p.$1]);
      final my = median([for (final p in xy) p.$2]);
      for (var i = 0; i < _window.length; i++) {
        final limit = math.max(outlierMinM, 3 * _window[i].accuracyM);
        final dx = xy[i].$1 - mx, dy = xy[i].$2 - my;
        if (dx * dx + dy * dy > limit * limit) keep[i] = false;
      }
      if (!keep.contains(true)) keep.fillRange(0, keep.length, true);
    }
    double sx = 0, sy = 0, sw = 0, sacc = 0;
    for (var i = 0; i < _window.length; i++) {
      final f = _window[i];
      if (!keep[i]) continue;
      final (x, y) = xy[i];
      final acc = math.max(1.0, f.accuracyM);
      final w = 1 / (acc * acc);
      sx += x * w;
      sy += y * w;
      sw += w;
      sacc += f.accuracyM;
    }
    _position = _projection.fromXY(sx / sw, sy / sw);
    _accuracyM = sacc / keep.where((k) => k).length;
    _distanceM = distanceM(_session.anchor, _position!);
  }

  Set<AlertReason> _activeAlarmConditions(DateTime now) {
    final r = <AlertReason>{};
    final delay = Duration(seconds: _p.alarmDelaySec);
    if (_outsideSince != null && now.difference(_outsideSince!) >= delay) {
      r.add(AlertReason.drag);
    }
    if (now.difference(_lastUsableFixAt) >= Duration(seconds: _p.gpsLostSec)) {
      r.add(AlertReason.gpsLost);
    }
    if (_batteryPct != null && !_charging && _batteryPct! <= _p.lowBatteryAlarmPct) {
      r.add(AlertReason.criticalBattery);
    }
    return r;
  }

  WatchSnapshot _evaluate(DateTime now) {
    final events = <AlertEvent>[];
    var radiusChanged = false;
    final gpsFresh =
        now.difference(_lastUsableFixAt) < Duration(seconds: _p.gpsLostSec);

    // Poor GPS: averaged accuracy over the threshold, or the latest fix too
    // inaccurate to be used at all.
    final poorNow = (gpsFresh && (_accuracyM ?? 0) > _p.poorAccuracyM) ||
        (_lastFix != null && _lastFix!.accuracyM > maxUsableAccuracyM);
    if (poorNow) {
      _poorSince ??= now;
    } else {
      _poorSince = null;
    }

    if (_distanceM != null && gpsFresh) {
      final d = _distanceM!;
      _maxDistanceM = math.max(_maxDistanceM, d);

      // Learn swing: widen (never shrink) while the boat settles, within a cap.
      if (_p.learnSwing &&
          now.difference(_startedAt) < learnSwingPeriod &&
          (_accuracyM ?? double.infinity) <= _p.poorAccuracyM &&
          d > _session.radiusM * learnSwingTrigger) {
        final cap = _session.initialRadiusM * learnSwingCap;
        final wanted = math.min(cap, d / learnSwingTrigger);
        if (wanted > _session.radiusM + 0.5) {
          _session = _session.copyWith(radiusM: wanted);
          radiusChanged = true;
        }
      }

      if (d > _session.warningRadiusM) {
        _nearEdgeSince ??= now;
      } else {
        _nearEdgeSince = null;
      }
      if (d > _session.radiusM) {
        _outsideSince ??= now;
      } else {
        _outsideSince = null;
      }
    }

    // Alarms: latch on rising edge.
    final alarmNow = _activeAlarmConditions(now);
    for (final r in alarmNow) {
      final rising = !_prevAlarms.contains(r);
      if (_latched.add(r) || (rising && _snoozedUntil != null)) {
        // A new alarm, or a snoozed one whose condition cleared and came back
        // (boat returned inside and left again), rings immediately.
        events.add(AlertEvent(reason: r, time: now, distanceM: _distanceM));
        _snoozedUntil = null;
      }
    }
    _prevAlarms = alarmNow;

    // Warnings: not latched, reported while true.
    final delay = Duration(seconds: _p.alarmDelaySec);
    final warnings = <AlertReason>{};
    if (_nearEdgeSince != null &&
        now.difference(_nearEdgeSince!) >= delay &&
        !alarmNow.contains(AlertReason.drag)) {
      warnings.add(AlertReason.nearEdge);
    }
    if (_poorSince != null && now.difference(_poorSince!) >= poorGpsDelay) {
      warnings.add(AlertReason.gpsPoor);
    }
    if (_batteryPct != null &&
        !_charging &&
        _batteryPct! <= _p.lowBatteryWarnPct &&
        !alarmNow.contains(AlertReason.criticalBattery)) {
      warnings.add(AlertReason.lowBattery);
    }
    for (final w in warnings.difference(_prevWarnings)) {
      events.add(AlertEvent(reason: w, time: now, distanceM: _distanceM));
    }
    _prevWarnings = warnings;

    final snoozed = _snoozedUntil != null && now.isBefore(_snoozedUntil!);
    if (_snoozedUntil != null && !snoozed) {
      _snoozedUntil = null;
      // Snooze expired: anything latched whose condition cleared is dropped,
      // anything still true rings again and is logged again.
      _latched.retainAll(alarmNow);
      for (final r in _latched) {
        events.add(AlertEvent(reason: r, time: now, distanceM: _distanceM));
      }
    }
    final ringing = _latched.isNotEmpty && !snoozed;

    if (events.isNotEmpty) {
      _session = _session.copyWith(alerts: [..._session.alerts, ...events]);
    }

    final reasons = {..._latched, ...warnings};
    final state = _latched.isNotEmpty
        ? WatchState.alarm
        : warnings.isNotEmpty
            ? WatchState.warning
            : WatchState.safe;

    return WatchSnapshot(
      time: now,
      state: state,
      reasons: reasons,
      ringing: ringing,
      radiusM: _session.radiusM,
      warningRadiusM: _session.warningRadiusM,
      maxDistanceM: _maxDistanceM,
      distanceM: _distanceM,
      bearingFromAnchorDeg:
          _position == null ? null : bearingDeg(_session.anchor, _position!),
      position: _position,
      accuracyM: _accuracyM,
      lastFix: _lastFix,
      outsideSince: _nearEdgeSince,
      snoozedUntil: snoozed ? _snoozedUntil : null,
      events: events,
      radiusChanged: radiusChanged,
    );
  }
}
