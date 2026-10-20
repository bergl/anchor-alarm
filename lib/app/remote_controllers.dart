import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../services/remote/remote_models.dart';
import '../services/remote/remote_services.dart';
import '../services/remote/remote_store.dart';
import 'providers.dart';
import 'watch_controller.dart';

/// Remote monitoring services, or null when this build has no Firebase
/// configuration (the UI then explains "Remote monitoring is not configured
/// in this build"). Overridden in main().
final remoteServicesProvider = Provider<RemoteServices?>((ref) => null);

/// A share link the app was opened with (web `#join=...`). Overridden in main().
final initialJoinLinkProvider = Provider<ShareLink?>((ref) => null);

// ---- Sharing this boat's watch -------------------------------------------

class ShareViewState {
  const ShareViewState({
    required this.configured,
    this.sessionId,
    this.record,
    this.busy = false,
    this.error,
    this.boatName = '',
  });

  final bool configured;

  /// The active local watch, if any.
  final String? sessionId;
  final ShareRecord? record;
  final bool busy;
  final String? error;
  final String boatName;

  bool get sharing => record?.active ?? false;

  ShareViewState copyWith({ShareRecord? record, bool? busy, String? error, bool clearError = false, String? boatName}) =>
      ShareViewState(
        configured: configured,
        sessionId: sessionId,
        record: record ?? this.record,
        busy: busy ?? this.busy,
        error: clearError ? null : error ?? this.error,
        boatName: boatName ?? this.boatName,
      );
}

/// "Share this watch" for the active local watch.
class ShareController extends Notifier<ShareViewState> {
  @override
  ShareViewState build() {
    final services = ref.watch(remoteServicesProvider);
    final sessionId = ref.watch(watchControllerProvider.select((s) => s.session?.id));
    if (services == null) return const ShareViewState(configured: false);
    final sub = services.sync.changes.listen((r) {
      if (r.sessionId == state.sessionId) state = state.copyWith(record: r);
    });
    ref.onDispose(sub.cancel);
    return ShareViewState(
      configured: true,
      sessionId: sessionId,
      record: sessionId == null ? null : services.sync.recordFor(sessionId),
      boatName: services.sync.boatName,
    );
  }

  Future<void> setBoatName(String name) async {
    final services = ref.read(remoteServicesProvider);
    if (services == null) return;
    await services.sync.setBoatName(name);
    state = state.copyWith(boatName: name.trim());
  }

  /// Starts uploading the active watch. Nothing is uploaded before this.
  Future<void> enable() async {
    final services = ref.read(remoteServicesProvider);
    final watch = ref.read(watchControllerProvider);
    final session = watch.session;
    if (services == null || session == null || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final rec = await services.sync.startSharing(session, watch.snapshot);
      state = state.copyWith(record: rec, busy: false);
    } catch (e) {
      debugPrint('Start sharing failed: $e');
      state = state.copyWith(
        busy: false,
        error: 'Could not reach the server. Check the connection and try again.',
      );
    }
  }

  /// Stops uploading, invalidates the link and removes everyone monitoring.
  Future<void> disable() async {
    final services = ref.read(remoteServicesProvider);
    final id = state.sessionId;
    if (services == null || id == null) return;
    await services.sync.stopSharing(id);
    state = state.copyWith(record: services.sync.recordFor(id), clearError: true);
  }
}

final shareControllerProvider =
    NotifierProvider<ShareController, ShareViewState>(ShareController.new);

// ---- Monitoring other boats ----------------------------------------------

enum JoinOutcome { joined, alreadyMonitoring, invalidLink, accessDenied, offline, failed, notConfigured }

class JoinResult {
  const JoinResult(this.outcome, [this.watchId]);
  final JoinOutcome outcome;
  final String? watchId;

  bool get ok => outcome == JoinOutcome.joined || outcome == JoinOutcome.alreadyMonitoring;

  String get message => switch (outcome) {
        JoinOutcome.joined => 'Monitoring started.',
        JoinOutcome.alreadyMonitoring => 'You are already monitoring this boat.',
        JoinOutcome.invalidLink => 'That is not a valid link or code.',
        JoinOutcome.accessDenied =>
          'This link is no longer valid. The boat may have stopped sharing — ask for a new link.',
        JoinOutcome.offline => 'No connection. Try again when online.',
        JoinOutcome.failed => 'Could not join. Try again.',
        JoinOutcome.notConfigured => 'Remote monitoring is not configured in this build.',
      };
}

/// The boats this device monitors (persisted).
class MonitoredBoatsController extends Notifier<List<MonitoredBoat>> {
  @override
  List<MonitoredBoat> build() => ref.watch(remoteServicesProvider)?.local.monitored ?? const [];

  /// Joins the watch in [input] (link or code).
  Future<JoinResult> join(String input, {String? deviceName}) async {
    final services = ref.read(remoteServicesProvider);
    if (services == null) return const JoinResult(JoinOutcome.notConfigured);
    final link = ShareLink.parse(input);
    if (link == null) return const JoinResult(JoinOutcome.invalidLink);
    final existing = state.where((b) => b.watchId == link.watchId).firstOrNull;
    if (existing != null && existing.shareKey == link.shareKey) {
      return JoinResult(JoinOutcome.alreadyMonitoring, link.watchId);
    }
    try {
      await services.push.requestPermission();
      final token = await services.push.token();
      await services.store.join(
        link.watchId,
        link.shareKey,
        fcmTokens: [?token],
        platform: services.platform,
        name: deviceName,
      );
    } on RemoteException catch (e) {
      return JoinResult(switch (e.kind) {
        RemoteErrorKind.accessDenied => JoinOutcome.accessDenied,
        RemoteErrorKind.offline => JoinOutcome.offline,
        RemoteErrorKind.other => JoinOutcome.failed,
      });
    } catch (e) {
      debugPrint('Join failed: $e');
      return const JoinResult(JoinOutcome.failed);
    }
    final boats = [
      for (final b in state)
        if (b.watchId != link.watchId) b,
      MonitoredBoat(watchId: link.watchId, shareKey: link.shareKey, addedAt: clock.now()),
    ];
    await services.local.saveMonitored(boats);
    state = boats;
    return JoinResult(JoinOutcome.joined, link.watchId);
  }

  /// Stops monitoring [watchId] on this device.
  Future<void> leave(String watchId) async {
    final services = ref.read(remoteServicesProvider);
    if (services == null) return;
    try {
      await services.store.leave(watchId);
    } catch (e) {
      debugPrint('Leave failed (removed locally anyway): $e');
    }
    final boats = [for (final b in state) if (b.watchId != watchId) b];
    await services.local.saveMonitored(boats);
    state = boats;
  }

  /// Remembers the boat name for the list.
  Future<void> rememberName(String watchId, String name) async {
    final services = ref.read(remoteServicesProvider);
    if (services == null || name.isEmpty) return;
    final i = state.indexWhere((b) => b.watchId == watchId);
    if (i < 0 || state[i].name == name) return;
    final boats = [...state]..[i] = state[i].copyWith(name: name);
    await services.local.saveMonitored(boats);
    state = boats;
  }
}

final monitoredBoatsProvider =
    NotifierProvider<MonitoredBoatsController, List<MonitoredBoat>>(MonitoredBoatsController.new);

enum MonitorProblem { accessDenied, offline, other }

class MonitorViewState {
  const MonitorViewState({
    required this.watchId,
    required this.now,
    this.watch,
    this.problem,
    this.silencedHere = false,
  });

  final String watchId;
  final RemoteWatch? watch;
  final MonitorProblem? problem;
  final DateTime now;

  /// The user silenced this device for the current alarm.
  final bool silencedHere;

  bool get loading => watch == null && problem == null;

  Freshness? get freshness => watch == null ? null : freshnessOf(watch!, now);

  /// The remote watch is ringing and this device should sound.
  bool get ringingHere =>
      problem == null && watch != null && watch!.ringing && !watch!.ended && !silencedHere;

  MonitorViewState copyWith({
    RemoteWatch? watch,
    MonitorProblem? problem,
    bool clearProblem = false,
    DateTime? now,
    bool? silencedHere,
  }) =>
      MonitorViewState(
        watchId: watchId,
        watch: watch ?? this.watch,
        problem: clearProblem ? null : problem ?? this.problem,
        now: now ?? this.now,
        silencedHere: silencedHere ?? this.silencedHere,
      );
}

/// Live view of one monitored boat. While its watch rings, this device
/// sounds its own local alarm; "Silence (here)" only silences this device.
class MonitorController extends Notifier<MonitorViewState> {
  MonitorController(this.watchId);
  final String watchId;

  StreamSubscription<RemoteWatch>? _sub;
  Timer? _ticker;
  bool _sirenOn = false;
  Set<AlertReason> _silencedReasons = const {};
  Freshness? _lastFreshness;

  @override
  MonitorViewState build() {
    final services = ref.watch(remoteServicesProvider);
    final alarm = ref.read(alarmOutputProvider);
    ref.onDispose(() {
      _sub?.cancel();
      _ticker?.cancel();
      if (_sirenOn) {
        _sirenOn = false;
        alarm.stopAlarm();
      }
    });
    final initial = MonitorViewState(watchId: watchId, now: clock.now());
    if (services == null) return initial.copyWith(problem: MonitorProblem.other);
    _sub = services.store.watch(watchId).listen(_onWatch, onError: (Object e) {
      final kind = e is RemoteException ? e.kind : RemoteErrorKind.other;
      state = state.copyWith(
        problem: switch (kind) {
          RemoteErrorKind.accessDenied => MonitorProblem.accessDenied,
          RemoteErrorKind.offline => MonitorProblem.offline,
          RemoteErrorKind.other => MonitorProblem.other,
        },
      );
      _syncAlarm();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return initial;
  }

  void _onWatch(RemoteWatch w) {
    var silenced = state.silencedHere;
    if (silenced) {
      // A silenced alarm stays silent until it stops on the boat or a new
      // alarm reason appears.
      final fresh = w.alarmReasons.difference(_silencedReasons);
      if (!w.ringing || fresh.isNotEmpty) silenced = false;
    }
    state = state.copyWith(watch: w, clearProblem: true, now: clock.now(), silencedHere: silenced);
    if (w.boatName.isNotEmpty) {
      unawaited(ref.read(monitoredBoatsProvider.notifier).rememberName(watchId, w.boatName));
    }
    _syncAlarm();
  }

  void _tick() {
    state = state.copyWith(now: clock.now());
    _syncAlarm();
  }

  /// Silences this device only; the boat keeps ringing until silenced there.
  Future<void> silenceHere() async {
    _silencedReasons = state.watch?.alarmReasons ?? const {};
    state = state.copyWith(silencedHere: true);
    _sirenOn = false;
    await ref.read(alarmOutputProvider).stopAlarm();
  }

  void _syncAlarm() {
    final alarm = ref.read(alarmOutputProvider);
    if (state.ringingHere) {
      if (!alarm.isRinging) {
        final profile = ref.read(activeProfileProvider);
        alarm.startAlarm(sound: profile.sound, vibrate: profile.vibrate);
      }
      _sirenOn = true;
    } else if (_sirenOn) {
      _sirenOn = false;
      if (alarm.isRinging) alarm.stopAlarm();
    }
    final f = state.freshness;
    if (f == Freshness.lost && _lastFreshness != null && _lastFreshness != Freshness.lost) {
      // Going silent is a warning, not an alarm: one chime here, plus the
      // "Lost contact" push from the server.
      alarm.chime(vibrate: true);
    }
    _lastFreshness = f;
  }
}

final monitorControllerProvider =
    NotifierProvider.family<MonitorController, MonitorViewState, String>(MonitorController.new);
