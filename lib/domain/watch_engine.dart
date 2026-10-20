import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'geo.dart';
import 'models.dart';

/// Fixes with accuracy worse than this are ignored for distance decisions
/// (they still count as "poor GPS" but not as a usable fix).
const double maxUsableAccuracyM = 100;

/// How long accuracy must stay poor before the poor-GPS warning is raised.
const Duration poorGpsDelay = Duration(minutes: 2);

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
        _startedAt = now,
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

  WatchSnapshot onFix(PositionFix fix) {
    _lastFix = fix;
    final now = fix.time;

    if (fix.accuracyM > _p.poorAccuracyM) {
      _poorSince ??= now;
    } else {
      _poorSince = null;
    }

    if (fix.accuracyM <= maxUsableAccuracyM) {
      _lastUsableFixAt = now;
      _window.add(fix);
      _trimWindow(now);
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
    double sx = 0, sy = 0, sw = 0, sacc = 0;
    for (final f in _window) {
      final (x, y) = _projection.toXY(f.position);
      final acc = math.max(1.0, f.accuracyM);
      final w = 1 / (acc * acc);
      sx += x * w;
      sy += y * w;
      sw += w;
      sacc += f.accuracyM;
    }
    _position = _projection.fromXY(sx / sw, sy / sw);
    _accuracyM = sacc / _window.length;
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
      if (_latched.add(r)) {
        events.add(AlertEvent(reason: r, time: now, distanceM: _distanceM));
        // A new alarm reason overrides an existing snooze.
        _snoozedUntil = null;
      }
    }

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
