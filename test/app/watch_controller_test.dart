import 'dart:async';

import 'package:anchor_alarm/app/providers.dart';
import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/services/alarm/alarm_output.dart';
import 'package:anchor_alarm/services/alarm/notification_service.dart';
import 'package:anchor_alarm/services/battery/battery_monitor.dart';
import 'package:anchor_alarm/services/heading/heading_source.dart';
import 'package:anchor_alarm/services/location/location_source.dart';
import 'package:anchor_alarm/services/storage/app_database.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// ---- Fakes ----------------------------------------------------------------

/// Hands out one single-subscription stream per [watch] call (like a real
/// platform stream) and feeds [emit]ted fixes to all open ones. (Cancelling a
/// broadcast subscription completes in the root zone, which fake_async does
/// not drive, so the fakes avoid broadcast streams.)
class FakeLocationSource implements LocationSource {
  final List<StreamController<PositionFix>> _open = [];
  final List<bool> watchCalls = [];

  @override
  String get label => 'Fake GPS';

  @override
  Future<LocationPermissionResult> requestPermission({bool background = false}) async =>
      LocationPermissionResult.always;

  @override
  Stream<PositionFix> watch({bool background = false}) {
    watchCalls.add(background);
    late final StreamController<PositionFix> c;
    c = StreamController<PositionFix>(onCancel: () async => _open.remove(c));
    _open.add(c);
    return c.stream;
  }

  void emit(PositionFix fix) {
    for (final c in List.of(_open)) {
      if (c.hasListener) c.add(fix);
    }
  }

  int get listeners => _open.where((c) => c.hasListener).length;

  @override
  Future<PositionFix?> currentFix() async => null;
}

class FakeHeadingSource implements HeadingSource {
  @override
  Future<bool> get available async => false;
  @override
  Stream<double?> get heading => const Stream.empty();
}

class FakeAlarmOutput implements AlarmOutput {
  final List<String> calls = [];
  bool _ringing = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> startAlarm({required String sound, required bool vibrate}) async {
    calls.add('start');
    _ringing = true;
  }

  @override
  Future<void> stopAlarm() async {
    calls.add('stop');
    _ringing = false;
  }

  @override
  Future<void> chime({required bool vibrate}) async => calls.add('chime');

  @override
  bool get isRinging => _ringing;
}

class FakeNotificationService implements NotificationService {
  final List<AlertReason> shown = [];
  final List<AlertReason> cancelled = [];
  final List<String> info = [];
  int cancelAllCount = 0;
  final actionsController = StreamController<String>.broadcast();

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showAlert({
    required AlertReason reason,
    required String title,
    required String body,
  }) async =>
      shown.add(reason);
  @override
  Future<void> showInfo({required String title, required String body}) async =>
      info.add(title);
  @override
  Future<void> cancelAlert(AlertReason reason) async => cancelled.add(reason);
  @override
  Future<void> cancelAll() async => cancelAllCount++;
  @override
  Stream<String> get actions => actionsController.stream;
}

class FakeBatteryMonitor implements BatteryMonitor {
  @override
  Stream<BatteryReading> get readings =>
      StreamController<BatteryReading>(onCancel: () async {}).stream;
}

// ---- Harness --------------------------------------------------------------

const anchor = LatLng(43.5, 16.4);
const radiusM = 30.0;

/// Deterministic profile: no averaging, no learn swing.
const profile = AlarmProfile(
  id: 'test',
  name: 'Test',
  alarmDelaySec: 10,
  averagingSec: 0,
  gpsLostSec: 60,
  learnSwing: false,
  snoozeSec: 120,
);

/// Position [northM] metres north of the anchor.
LatLng north(double northM) =>
    LatLng(anchor.latitude + northM / 111195.0, anchor.longitude);

class Harness {
  Harness(this.async, this.db) {
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      settingsRepositoryProvider.overrideWithValue(db.settings),
      sessionRepositoryProvider.overrideWithValue(db.sessions),
      deviceLocationProvider.overrideWithValue(location),
      deviceHeadingProvider.overrideWithValue(FakeHeadingSource()),
      alarmOutputProvider.overrideWithValue(alarm),
      notificationServiceProvider.overrideWithValue(notifications),
      batteryMonitorProvider.overrideWithValue(battery),
    ]);
    // Keep the controller alive like the UI would.
    container.listen(watchControllerProvider, (_, _) {});
    async.flushMicrotasks();
  }

  final FakeAsync async;
  final AppDatabase db;
  final location = FakeLocationSource();
  final alarm = FakeAlarmOutput();
  final notifications = FakeNotificationService();
  final battery = FakeBatteryMonitor();
  late final ProviderContainer container;

  WatchController get controller => container.read(watchControllerProvider.notifier);
  WatchViewState get state => container.read(watchControllerProvider);

  /// Waits for [f] while letting fake time advance in small steps.
  T wait<T>(Future<T> f) {
    late T result;
    Object? error;
    var done = false;
    f.then<void>((v) {
      result = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 1000 && !done; i++) {
      async.flushMicrotasks();
      if (!done) async.elapse(const Duration(milliseconds: 1));
    }
    if (error != null) throw error!;
    if (!done) fail('future did not complete');
    return result;
  }

  void start() => wait(controller.startWatch(
        anchor: anchor,
        radiusM: radiusM,
        profile: profile,
        rodeM: 30,
        depthM: 5,
      ));

  /// Emits one fix at the current fake time [northM] metres from the anchor.
  void fix(double northM, {double acc = 4}) {
    location.emit(PositionFix(
      position: north(northM),
      accuracyM: acc,
      time: clock.now(),
    ));
    async.flushMicrotasks();
  }

  /// Emits a fix every second for [seconds] seconds.
  void fixesFor(int seconds, double northM) {
    for (var i = 0; i < seconds; i++) {
      async.elapse(const Duration(seconds: 1));
      fix(northM);
    }
  }

  void dispose() {
    async.elapse(const Duration(milliseconds: 100));
    container.dispose();
    async.elapse(const Duration(milliseconds: 100));
    wait(db.close());
  }
}

/// Runs [body] in fake time with a fresh in-memory database.
void runFake(void Function(Harness h) body) {
  fakeAsync((async) {
    late AppDatabase database;
    var opened = false;
    openAppDatabase(inMemory: true).then((d) {
      database = d;
      opened = true;
    });
    while (!opened) {
      async.elapse(const Duration(milliseconds: 1));
    }
    final h = Harness(async, database);
    try {
      body(h);
    } finally {
      h.dispose();
    }
  }, initialTime: DateTime(2026, 10, 20, 22));
}

void main() {
  test('start watch, fixes inside the warning ring → safe', () {
    runFake((h) {
      h.start();
      expect(h.state.watching, isTrue);
      expect(h.location.watchCalls.last, isTrue, reason: 'background stream while watching');

      h.fixesFor(15, 10);
      final snap = h.state.snapshot!;
      expect(snap.state, WatchState.safe);
      expect(snap.distanceM, closeTo(10, 0.5));
      expect(h.alarm.calls, isNot(contains('start')));
      expect(h.notifications.shown, isEmpty);

      // The session was persisted when the watch started.
      final saved = h.wait(h.db.sessions.loadActive());
      expect(saved!.id, h.state.session!.id);
      expect(saved.rodeM, 30);
    });
  });

  test('each fix is processed once (no duplicate location subscriptions)', () {
    runFake((h) {
      h.start();
      // Several resubscriptions happened (build, start engine, permission).
      expect(h.location.watchCalls.length, greaterThanOrEqualTo(2));
      var count = 0;
      final sub = h.container.listen(
        watchControllerProvider.select((s) => s.snapshot?.lastFix),
        (_, _) => count++,
      );
      expect(h.location.listeners, 1);
      h.fix(5);
      expect(count, 1);
      sub.close();
    });
  });

  test('outside the alarm ring long enough → alarm, notification, persisted alert', () {
    runFake((h) {
      h.start();
      h.fixesFor(5, 10);
      expect(h.state.snapshot!.state, WatchState.safe);

      // Drag: 50 m from the anchor, radius 30 m, delay 10 s.
      h.fixesFor(5, 50);
      expect(h.state.snapshot!.state, isNot(WatchState.alarm));
      expect(h.alarm.isRinging, isFalse);

      h.fixesFor(7, 50);
      final snap = h.state.snapshot!;
      expect(snap.state, WatchState.alarm);
      expect(snap.reasons, contains(AlertReason.drag));
      expect(snap.ringing, isTrue);
      expect(h.alarm.isRinging, isTrue);
      expect(h.alarm.calls.where((c) => c == 'start'), hasLength(1));
      expect(h.notifications.shown, contains(AlertReason.drag));

      h.async.flushMicrotasks();
      final saved = h.wait(h.db.sessions.get(h.state.session!.id))!;
      expect(saved.alerts.map((a) => a.reason), contains(AlertReason.drag));
      expect(saved.maxDistanceM, greaterThan(45));
    });
  });

  test('acknowledge stops the alarm; back inside clears it', () {
    runFake((h) {
      h.start();
      h.fixesFor(15, 50);
      expect(h.alarm.isRinging, isTrue);

      h.wait(h.controller.acknowledge());
      expect(h.alarm.isRinging, isFalse);
      expect(h.alarm.calls.last, 'stop');
      expect(h.state.snapshot!.ringing, isFalse);
      expect(h.state.snapshot!.snoozedUntil, isNotNull, reason: 'still outside → snoozed');

      // Boat comes back inside: after the snooze nothing rings again.
      h.fixesFor(130, 5);
      expect(h.alarm.isRinging, isFalse);
      expect(h.state.snapshot!.state, WatchState.safe);
      expect(h.notifications.cancelled, contains(AlertReason.drag));

      final saved = h.wait(h.db.sessions.get(h.state.session!.id))!;
      final drag = saved.alerts.firstWhere((a) => a.reason == AlertReason.drag);
      expect(drag.acknowledgedAt, isNotNull);
    });
  });

  test('snooze expires while still outside → alarm rings again', () {
    runFake((h) {
      h.start();
      h.fixesFor(15, 50);
      h.wait(h.controller.acknowledge());
      expect(h.alarm.isRinging, isFalse);
      h.fixesFor(125, 50);
      expect(h.alarm.isRinging, isTrue);
    });
  });

  test('notification "silence" action acknowledges the alarm', () {
    runFake((h) {
      h.start();
      h.fixesFor(15, 50);
      expect(h.alarm.isRinging, isTrue);
      h.notifications.actionsController.add(NotificationActions.silence);
      h.async.flushMicrotasks();
      expect(h.alarm.isRinging, isFalse);
    });
  });

  test('GPS lost raises the alarm via the ticker', () {
    runFake((h) {
      h.start();
      h.fixesFor(3, 5);
      h.async.elapse(const Duration(seconds: 61));
      expect(h.state.snapshot!.reasons, contains(AlertReason.gpsLost));
      expect(h.alarm.isRinging, isTrue);
    });
  });

  test('stopWatch → session in history with endedAt and track points', () {
    runFake((h) {
      h.start();
      h.fixesFor(40, 10);
      final id = h.state.session!.id;
      h.wait(h.controller.stopWatch(notes: 'Calm night', name: 'Test bay'));

      expect(h.state.watching, isFalse);
      expect(h.notifications.cancelAllCount, 1);
      expect(h.wait(h.db.sessions.loadActive()), isNull);

      final history = h.wait(h.db.sessions.history());
      expect(history, hasLength(1));
      final s = history.single;
      expect(s.id, id);
      expect(s.endedAt, isNotNull);
      expect(s.notes, 'Calm night');
      expect(s.name, 'Test bay');
      expect(s.endedAt!.difference(s.startedAt).inSeconds, closeTo(40, 2));

      final track = h.wait(h.db.sessions.track(id));
      // Recorder keeps a point at least every 30 s (minimum 5 s apart).
      expect(track.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < track.length; i++) {
        expect(track[i].time.isAfter(track[i - 1].time), isTrue);
      }

      // Fixes after stopping are shown but not recorded.
      h.fixesFor(2, 10);
      expect(h.state.fix, isNotNull);
      expect(h.state.snapshot, isNull);
      expect(h.location.watchCalls.last, isFalse);
    });
  });

  test('restore() resumes the active session from the repository', () {
    fakeAsync((async) {
      late AppDatabase db;
      openAppDatabase(inMemory: true).then((d) => db = d);
      async.elapse(const Duration(milliseconds: 50));

      final active = AnchorSession(
        id: 'resume-me',
        anchor: anchor,
        radiusM: radiusM,
        initialRadiusM: radiusM,
        profile: profile,
        startedAt: clock.now().subtract(const Duration(hours: 3)),
      );
      db.sessions.save(active);
      async.elapse(const Duration(milliseconds: 50));

      final h = Harness(async, db);
      try {
        expect(h.state.watching, isFalse);
        h.wait(h.controller.restore());
        expect(h.state.watching, isTrue);
        expect(h.state.resumed, isTrue);
        expect(h.state.session!.id, 'resume-me');
        expect(h.notifications.info, isNotEmpty);
        expect(h.location.watchCalls.last, isTrue);

        // Watching resumes normally.
        h.fixesFor(15, 50);
        expect(h.state.snapshot!.state, WatchState.alarm);

        // A second restore is a no-op.
        h.wait(h.controller.restore());
        expect(h.notifications.info, hasLength(1));
      } finally {
        h.dispose();
      }
    }, initialTime: DateTime(2026, 10, 20, 22));
  });

  test('restore() without an active session does nothing', () {
    runFake((h) {
      h.wait(h.controller.restore());
      expect(h.state.watching, isFalse);
      expect(h.notifications.info, isEmpty);
    });
  });
}
