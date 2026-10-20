import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../domain/geo.dart';
import '../domain/models.dart';
import '../domain/track_recorder.dart';
import '../domain/watch_engine.dart';
import '../services/alarm/notification_service.dart';
import '../services/location/location_source.dart';
import 'format.dart';
import 'providers.dart';

/// Anchor position and radius being prepared before the watch starts.
class AnchorDraft {
  const AnchorDraft({
    required this.anchor,
    required this.radiusM,
    this.rodeM,
    this.depthM,
  });

  final LatLng anchor;
  final double radiusM;
  final double? rodeM;
  final double? depthM;

  AnchorDraft copyWith({LatLng? anchor, double? radiusM, double? rodeM, double? depthM}) =>
      AnchorDraft(
        anchor: anchor ?? this.anchor,
        radiusM: radiusM ?? this.radiusM,
        rodeM: rodeM ?? this.rodeM,
        depthM: depthM ?? this.depthM,
      );
}

class WatchViewState {
  const WatchViewState({
    this.session,
    this.snapshot,
    this.fix,
    this.draft,
    this.permission,
    this.sourceLabel = '',
    this.resumed = false,
  });

  /// The active watch, or null when not watching.
  final AnchorSession? session;
  final WatchSnapshot? snapshot;

  /// Latest raw fix, also while not watching (to show the boat on the map).
  final PositionFix? fix;

  /// Anchor being placed before the watch starts.
  final AnchorDraft? draft;
  final LocationPermissionResult? permission;
  final String sourceLabel;

  /// The active watch was restored after an app restart.
  final bool resumed;

  bool get watching => session != null;

  WatchViewState copyWith({
    AnchorSession? session,
    bool clearSession = false,
    WatchSnapshot? snapshot,
    bool clearSnapshot = false,
    PositionFix? fix,
    AnchorDraft? draft,
    bool clearDraft = false,
    LocationPermissionResult? permission,
    String? sourceLabel,
    bool? resumed,
  }) =>
      WatchViewState(
        session: clearSession ? null : session ?? this.session,
        snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
        fix: fix ?? this.fix,
        draft: clearDraft ? null : draft ?? this.draft,
        permission: permission ?? this.permission,
        sourceLabel: sourceLabel ?? this.sourceLabel,
        resumed: resumed ?? this.resumed,
      );
}

/// Orchestrates the anchor watch: location → engine → alarm, notifications,
/// persistence, track and remote sync.
class WatchController extends Notifier<WatchViewState> {
  AnchorWatchEngine? _engine;
  StreamSubscription<PositionFix>? _locSub;
  StreamSubscription<Object?>? _batterySub;
  StreamSubscription<String>? _actionSub;
  Timer? _ticker;
  TrackRecorder _recorder = TrackRecorder();
  final List<TrackPoint> _pendingTrack = [];

  /// Alert notifications currently shown.
  final Set<AlertReason> _shownAlerts = {};

  /// The siren is sounding for this watch.
  bool _sirenOn = false;
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTrackFlush = DateTime.fromMillisecondsSinceEpoch(0);

  static const _persistEvery = Duration(seconds: 15);
  static const _publishEvery = Duration(seconds: 5);
  static const _flushTrackEvery = Duration(seconds: 60);

  @override
  WatchViewState build() {
    // Switching between device GPS and simulator restarts the location stream.
    ref.listen(locationSourceProvider, (_, _) => _subscribeLocation());
    _actionSub = ref.read(notificationServiceProvider).actions.listen((a) {
      if (a == NotificationActions.silence) acknowledge();
    });
    ref.onDispose(() {
      _locSub?.cancel();
      _batterySub?.cancel();
      _actionSub?.cancel();
      _ticker?.cancel();
    });
    Future.microtask(_subscribeLocation);
    return const WatchViewState();
  }

  /// `clock` (package:clock) so tests can control time with fake_async.
  DateTime _now() => clock.now();

  /// Restores a watch that was active when the app was last closed.
  /// Safe to call more than once: only the first call restores.
  Future<void> restore() => _restoring ??= _restore();
  Future<void>? _restoring;

  Future<void> _restore() async {
    final s = await ref.read(sessionRepositoryProvider).loadActive();
    if (s == null || state.watching) return;
    _startEngine(s);
    state = state.copyWith(resumed: true);
    await ref.read(notificationServiceProvider).showInfo(
          title: 'Anchor watch resumed',
          body: 'The anchor watch was restored after the app restarted.',
        );
  }

  /// Ask for location permission (background when [background]) and (re)start
  /// the location stream.
  Future<LocationPermissionResult> requestPermission({bool background = false}) async {
    final res = await ref
        .read(locationSourceProvider)
        .requestPermission(background: background);
    state = state.copyWith(permission: res);
    await _subscribeLocation();
    return res;
  }

  int _subscribeGen = 0;

  Future<void> _subscribeLocation() async {
    // Calls can overlap (build, _startEngine and requestPermission all
    // resubscribe); only the newest one may listen, otherwise a stale
    // subscription would keep delivering every fix a second time.
    final gen = ++_subscribeGen;
    final old = _locSub;
    _locSub = null;
    await old?.cancel();
    if (gen != _subscribeGen || !ref.mounted) return;
    final src = ref.read(locationSourceProvider);
    state = state.copyWith(sourceLabel: src.label);
    _locSub = src.watch(background: state.watching).listen(
          _onFix,
          onError: (Object e) {
            // Permission revoked or service disabled; GPS-lost alarm covers the watch.
          },
        );
  }

  // ---- Draft (before starting) ------------------------------------------

  void setDraft(AnchorDraft draft) => state = state.copyWith(draft: draft);
  void clearDraft() => state = state.copyWith(clearDraft: true);

  // ---- Watch lifecycle ---------------------------------------------------

  Future<void> startWatch({
    required LatLng anchor,
    required double radiusM,
    required AlarmProfile profile,
    double? rodeM,
    double? depthM,
  }) async {
    final session = AnchorSession(
      id: const Uuid().v4(),
      anchor: anchor,
      radiusM: radiusM,
      initialRadiusM: radiusM,
      profile: profile,
      startedAt: _now(),
      rodeM: rodeM,
      depthM: depthM,
    );
    final settings = ref.read(settingsProvider);
    if (settings.useSimulator) {
      // Make the simulated boat lie to this anchor on the rode the user entered,
      // so demos behave like a real anchorage.
      final sim = ref.read(simulatorProvider);
      if (rodeM != null && depthM != null) {
        sim.rodeM = horizontalRodeM(rodeM: rodeM, depthM: depthM) +
            settings.boat.gpsToBowM;
      }
      sim.relocate(anchor);
    }
    await ref.read(notificationServiceProvider).requestPermission();
    await ref.read(sessionRepositoryProvider).save(session);
    _startEngine(session);
    state = state.copyWith(clearDraft: true, resumed: false);
    await requestPermission(background: true);
  }

  void _startEngine(AnchorSession session) {
    _engine = AnchorWatchEngine(session: session, now: _now());
    _recorder = TrackRecorder();
    _pendingTrack.clear();
    state = state.copyWith(session: session, clearSnapshot: true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final e = _engine;
      if (e != null) _handle(e.onTick(_now()));
    });
    _batterySub?.cancel();
    _batterySub = ref.read(batteryMonitorProvider).readings.listen((b) {
      final e = _engine;
      if (e != null) {
        _handle(e.onBattery(levelPct: b.levelPct, charging: b.charging, now: _now()));
      }
    });
    _subscribeLocation();
  }

  Future<void> stopWatch({String? notes, String? name}) async {
    final e = _engine;
    if (e == null) return;
    _engine = null;
    _ticker?.cancel();
    await _batterySub?.cancel();
    final ended = e.session.copyWith(endedAt: _now(), notes: notes, name: name);
    _sirenOn = false;
    await ref.read(alarmOutputProvider).stopAlarm();
    await ref.read(notificationServiceProvider).cancelAll();
    _shownAlerts.clear();
    await _flushTrack(ended.id);
    await ref.read(sessionRepositoryProvider).save(ended);
    await ref.read(remoteSyncProvider).end(ended);
    state = state.copyWith(clearSession: true, clearSnapshot: true, resumed: false);
    await _subscribeLocation();
  }

  /// Move the anchor (e.g. dragged on the map) while watching.
  void moveAnchor(LatLng anchor) => _updateSession((s) => s.copyWith(anchor: anchor));

  void setRadius(double radiusM) =>
      _updateSession((s) => s.copyWith(radiusM: radiusM, initialRadiusM: radiusM));

  /// Accept a learn-swing suggestion. Unlike [setRadius] this keeps the
  /// initial radius, so suggestions stay capped relative to the original.
  void acceptSwingSuggestion(double radiusM) =>
      _updateSession((s) => s.copyWith(radiusM: radiusM));

  void setProfile(AlarmProfile profile) => _updateSession((s) => s.copyWith(profile: profile));

  void _updateSession(AnchorSession Function(AnchorSession) change) {
    final e = _engine;
    if (e == null) return;
    e.updateSession(change(e.session));
    _handle(e.onTick(_now()), forcePersist: true);
  }

  /// Silence the alarm (snoozes if the condition persists).
  Future<void> acknowledge() async {
    final e = _engine;
    await ref.read(alarmOutputProvider).stopAlarm();
    if (e == null) return;
    _handle(e.acknowledge(_now()), forcePersist: true);
  }

  // ---- Fix handling ------------------------------------------------------

  void _onFix(PositionFix fix) {
    final e = _engine;
    if (e == null) {
      state = state.copyWith(fix: fix);
      return;
    }
    final snap = e.onFix(fix, receivedAt: _now());
    final p = _recorder.offer(fix, alarm: snap.state == WatchState.alarm);
    if (p != null) _pendingTrack.add(p);
    _handle(snap, fix: fix);
  }

  void _handle(WatchSnapshot snap, {PositionFix? fix, bool forcePersist = false}) {
    final e = _engine;
    if (e == null) return;
    final session = e.session;
    final profile = session.profile;
    final now = snap.time;

    final alarm = ref.read(alarmOutputProvider);
    final notes = ref.read(notificationServiceProvider);
    final unit = ref.read(settingsProvider).distanceUnit;

    for (final ev in snap.events) {
      _shownAlerts.add(ev.reason);
      notes.showAlert(
        reason: ev.reason,
        title: alertTitle(ev.reason),
        body: alertBody(ev.reason,
            distanceM: snap.distanceM, radiusM: snap.radiusM, unit: unit),
      );
      if (!ev.reason.isAlarm) alarm.chime(vibrate: profile.vibrate);
    }
    // Only stop a siren this watch started: the same output also sounds
    // alarms of boats monitored remotely from this device.
    if (snap.ringing) {
      if (!alarm.isRinging) {
        alarm.startAlarm(sound: profile.sound, vibrate: profile.vibrate);
      }
      _sirenOn = true;
    } else if (_sirenOn) {
      _sirenOn = false;
      if (alarm.isRinging) alarm.stopAlarm();
    }
    // Clear notifications of warnings that are no longer active and of
    // alarms that were acknowledged and have cleared.
    for (final r in _shownAlerts.difference(snap.reasons)) {
      notes.cancelAlert(r);
    }
    _shownAlerts.retainAll(snap.reasons);

    state = state.copyWith(session: session, snapshot: snap, fix: fix);

    final repo = ref.read(sessionRepositoryProvider);
    if (forcePersist ||
        snap.events.isNotEmpty ||
        now.difference(_lastPersist) >= _persistEvery) {
      _lastPersist = now;
      repo.save(session);
    }
    if (_pendingTrack.length >= 20 || now.difference(_lastTrackFlush) >= _flushTrackEvery) {
      _flushTrack(session.id);
    }
    if (snap.events.isNotEmpty || now.difference(_lastPublish) >= _publishEvery) {
      _lastPublish = now;
      ref.read(remoteSyncProvider).publish(session, snap);
    }
  }

  Future<void> _flushTrack(String sessionId) async {
    _lastTrackFlush = _now();
    if (_pendingTrack.isEmpty) return;
    final batch = List<TrackPoint>.of(_pendingTrack);
    _pendingTrack.clear();
    await ref.read(sessionRepositoryProvider).appendTrack(sessionId, batch);
  }
}

final watchControllerProvider =
    NotifierProvider<WatchController, WatchViewState>(WatchController.new);
