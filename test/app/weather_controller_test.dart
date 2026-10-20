import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/app/providers.dart';
import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/app/weather_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/weather.dart';
import 'package:anchor_alarm/services/storage/repositories.dart';
import 'package:anchor_alarm/services/weather/weather_service.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../ui/fakes.dart';

class TestWatchController extends WatchController {
  @override
  WatchViewState build() => const WatchViewState();
  void set(WatchViewState s) => state = s;
}

class RecordingNotifications extends FakeNotificationService {
  final infos = <({String title, String body})>[];

  @override
  Future<void> showInfo({required String title, required String body}) async =>
      infos.add((title: title, body: body));
}

final t0 = DateTime.utc(2026, 10, 20, 20);
const anchor = LatLng(43.508, 16.44);
const boat = LatLng(43.6, 16.5);

AnchorSession session([String id = 's1']) => AnchorSession(
      id: id,
      anchor: anchor,
      radiusM: 40,
      initialRadiusM: 40,
      profile: AlarmProfile.builtIns[1],
      startedAt: t0,
    );

/// 30 hourly steps from the current hour; gusts of [gustKn] from
/// [gustAt] (absolute time) for two hours, otherwise calm.
Forecast forecastAt(DateTime now, LatLng p, {DateTime? gustAt, double gustKn = 30}) {
  final start = DateTime.utc(now.year, now.month, now.day, now.hour);
  return Forecast(
    fetchedAt: now,
    location: p,
    hourly: [
      for (var i = 0; i < 30; i++)
        (() {
          final t = start.add(Duration(hours: i));
          final gusty = gustAt != null &&
              !t.isBefore(gustAt) &&
              t.isBefore(gustAt.add(const Duration(hours: 2)));
          return WeatherConditions(
            time: t,
            windKn: 8,
            gustKn: gusty ? gustKn : 12,
            windDirDeg: 315,
            pressureHpa: 1015,
          );
        })(),
    ],
  );
}

class Env {
  Env({AppSettings settings = const AppSettings(), Forecast? cached})
      : repo = MemoryWeatherRepository(cached),
        settingsRepo = InMemorySettingsRepository(settings) {
    service.respond = (p) => online
        ? WeatherOk(forecastAt(clock.now().toUtc(), p, gustAt: gustAt, gustKn: gustKn))
        : const WeatherError('No connection to the weather service');
    container = ProviderContainer(overrides: [
      initialSettingsProvider.overrideWithValue(settings),
      settingsRepositoryProvider.overrideWithValue(settingsRepo),
      watchControllerProvider.overrideWith(TestWatchController.new),
      weatherServiceProvider.overrideWithValue(service),
      weatherRepositoryProvider.overrideWithValue(repo),
      notificationServiceProvider.overrideWithValue(notifications),
      alarmOutputProvider.overrideWithValue(alarm),
    ]);
    // Keep it alive, as the map screen does.
    container.listen(weatherControllerProvider, (_, _) {});
  }

  late final ProviderContainer container;
  final service = FakeWeatherService();
  final MemoryWeatherRepository repo;
  final InMemorySettingsRepository settingsRepo;
  final notifications = RecordingNotifications();
  final alarm = FakeAlarmOutput();
  bool online = true;
  DateTime? gustAt;
  double gustKn = 30;

  WeatherState get state => container.read(weatherControllerProvider);
  WeatherController get ctrl => container.read(weatherControllerProvider.notifier);
  TestWatchController get watch =>
      container.read(watchControllerProvider.notifier) as TestWatchController;

  void startWatch() => watch.set(WatchViewState(session: session()));
  void stopWatch() => watch.set(const WatchViewState());
  void setFix(LatLng p) => watch.set(WatchViewState(
      fix: PositionFix(position: p, accuracyM: 5, time: clock.now())));
}

void run(void Function(FakeAsync async, Env env) body,
    {AppSettings settings = const AppSettings(), Forecast? cached}) {
  fakeAsync((async) {
    withClock(async.getClock(t0), () {
      final env = Env(settings: settings, cached: cached);
      async.flushMicrotasks();
      body(async, env);
      env.container.dispose();
    });
  });
}

void main() {
  test('nothing is fetched until a watch starts', () {
    run((async, env) {
      async.elapse(const Duration(hours: 4));
      expect(env.service.queries, isEmpty);
      expect(env.state.forecast, isNull);
    });
  });

  test('fetches for the anchor on watch start, caches it, then every 3 h', () {
    run((async, env) {
      env.startWatch();
      async.flushMicrotasks();
      expect(env.service.queries, [anchor]);
      expect(env.state.forecast!.fetchedAt, t0);
      expect(env.state.risk, isNotNull);
      expect(env.state.loading, isFalse);
      expect(env.repo.saves, 1);

      async.elapse(const Duration(hours: 2, minutes: 59));
      expect(env.service.queries, hasLength(1));
      async.elapse(const Duration(minutes: 1));
      expect(env.service.queries, hasLength(2));
      async.elapse(const Duration(hours: 3));
      expect(env.service.queries, hasLength(3));
      expect(env.repo.saves, 3);
      expect(env.state.forecast!.fetchedAt, t0.add(const Duration(hours: 6)));

      // Stopping the watch stops the refresh.
      env.stopWatch();
      async.elapse(const Duration(hours: 9));
      expect(env.service.queries, hasLength(3));
    });
  });

  test('offline: keeps the cached forecast, shows the error, retries every 30 min', () {
    final cached = forecastAt(t0.subtract(const Duration(hours: 5)), anchor);
    run(cached: cached, (async, env) {
      expect(env.state.forecast, same(cached), reason: 'cache loaded on start');
      expect(env.state.isStale(t0), isTrue);
      env.online = false;
      env.startWatch();
      async.flushMicrotasks();
      expect(env.service.queries, hasLength(1));
      expect(env.state.error, 'No connection to the weather service');
      expect(env.state.forecast, same(cached));
      expect(env.state.risk, isNotNull);

      async.elapse(const Duration(minutes: 15));
      expect(env.service.queries, hasLength(1), reason: 'no retry before 30 min');
      async.elapse(const Duration(minutes: 15));
      expect(env.service.queries, hasLength(2));

      env.online = true;
      async.elapse(const Duration(minutes: 30));
      expect(env.service.queries, hasLength(3));
      expect(env.state.error, isNull);
      expect(env.state.forecast!.fetchedAt, t0.add(const Duration(hours: 1)));
      expect(env.repo.forecast, same(env.state.forecast));
    });
  });

  test('forecast alert notified about 2 h ahead, once; never the siren', () {
    run((async, env) {
      env.gustAt = t0.add(const Duration(hours: 5)); // 01:00
      env.startWatch();
      async.flushMicrotasks();
      expect(env.state.hasAlerts, isTrue);
      expect(env.notifications.infos, isEmpty, reason: '5 h ahead');

      async.elapse(const Duration(hours: 2, minutes: 45));
      expect(env.notifications.infos, isEmpty);
      async.elapse(const Duration(minutes: 15)); // 3 h: 2 h before the gusts
      expect(env.notifications.infos, hasLength(1));
      expect(env.notifications.infos.single.title, 'Strong gusts forecast');
      expect(env.notifications.infos.single.body, startsWith('Gusts to 30 kn expected around'));

      // Later ticks and refreshes of the same event: no repeat.
      async.elapse(const Duration(hours: 6));
      expect(env.service.queries.length, greaterThanOrEqualTo(3));
      expect(env.notifications.infos, hasLength(1));
      expect(env.alarm.starts, 0);
    });
  });

  test('alert already within 2 h → notified at once; escalation notifies again', () {
    run((async, env) {
      env.gustAt = t0.add(const Duration(hours: 1));
      env.startWatch();
      async.flushMicrotasks();
      expect(env.notifications.infos, hasLength(1));

      // Moved by an hour in the next forecast: same event.
      env.gustAt = t0.add(const Duration(hours: 2));
      env.ctrl.refresh();
      async.flushMicrotasks();
      expect(env.notifications.infos, hasLength(1));

      // Much stronger: notify again.
      env.gustKn = 40;
      env.ctrl.refresh();
      async.flushMicrotasks();
      expect(env.notifications.infos, hasLength(2));
      expect(env.notifications.infos.last.body, contains('40 kn'));
    });
  });

  test('several alerts due together → one combined notification', () {
    run((async, env) {
      env.gustAt = t0.add(const Duration(hours: 1));
      env.gustKn = 30;
      env.startWatch();
      async.flushMicrotasks();
      expect(env.notifications.infos, hasLength(1));
      // Lower wind threshold: a new kind becomes due.
      env.container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(windWarnKn: 8, gustWarnKn: 12));
      async.flushMicrotasks();
      expect(env.notifications.infos, hasLength(2));
      expect(env.notifications.infos.last.title, 'Strong wind forecast');
    });
  });

  test('alerts switched off → no notifications', () {
    run(settings: const AppSettings(weatherAlerts: false), (async, env) {
      env.gustAt = t0.add(const Duration(hours: 1));
      env.startWatch();
      async.flushMicrotasks();
      expect(env.state.hasAlerts, isTrue);
      async.elapse(const Duration(hours: 4));
      expect(env.notifications.infos, isEmpty);
    });
  });

  test('not watching: no notifications even with alerts', () {
    run((async, env) {
      env.gustAt = t0.add(const Duration(hours: 1));
      env.setFix(boat);
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.state.hasAlerts, isTrue);
      expect(env.notifications.infos, isEmpty);
    });
  });

  test('ensureFresh (weather sheet) fetches for the boat when needed', () {
    run((async, env) {
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.service.queries, isEmpty, reason: 'no position yet');

      env.setFix(boat);
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.service.queries, [boat]);

      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.service.queries, hasLength(1), reason: 'fresh enough');

      async.elapse(const Duration(hours: 1));
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.service.queries, hasLength(2), reason: '1 h old');

      // Far away (> 5 km): fetch again.
      env.setFix(const LatLng(44, 16.5));
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.service.queries, hasLength(3));
    });
  });

  test('ensureFresh after a failure waits 5 min', () {
    run((async, env) {
      env.online = false;
      env.setFix(boat);
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.service.queries, hasLength(1));
      async.elapse(const Duration(minutes: 5));
      env.ctrl.ensureFresh();
      async.flushMicrotasks();
      expect(env.service.queries, hasLength(2));
    });
  });

  test('app resume while watching refreshes a stale forecast', () {
    run((async, env) {
      env.startWatch();
      async.flushMicrotasks();
      env.ctrl.onAppResumed();
      async.flushMicrotasks();
      expect(env.service.queries, hasLength(1), reason: 'still fresh');
      // Timers do not run while the app is suspended: jump the clock only.
      async.elapse(const Duration(hours: 3, minutes: 1));
      final n = env.service.queries.length;
      env.ctrl.onAppResumed();
      async.flushMicrotasks();
      expect(env.service.queries.length, n, reason: 'tick already refreshed');
    });
  });

  test('watch restored after the controller was created', () {
    run((async, env) {
      async.elapse(const Duration(minutes: 1));
      env.startWatch();
      async.flushMicrotasks();
      expect(env.service.queries, [anchor]);
    });
  });

  test('controller created while a watch is already active', () {
    fakeAsync((async) {
      withClock(async.getClock(t0), () {
        final env = Env();
        // Recreate: the watch is active before the weather controller exists.
        final c = ProviderContainer(overrides: [
          watchControllerProvider.overrideWith(TestWatchController.new),
          weatherServiceProvider.overrideWithValue(env.service),
          weatherRepositoryProvider.overrideWithValue(MemoryWeatherRepository()),
          notificationServiceProvider.overrideWithValue(env.notifications),
          settingsRepositoryProvider.overrideWithValue(env.settingsRepo),
        ]);
        (c.read(watchControllerProvider.notifier) as TestWatchController)
            .set(WatchViewState(session: session()));
        c.listen(weatherControllerProvider, (_, _) {});
        async.flushMicrotasks();
        expect(env.service.queries, [anchor]);
        c.dispose();
        env.container.dispose();
      });
    });
  });

  test('thresholds from settings re-analyse the forecast', () {
    run((async, env) {
      env.startWatch();
      async.flushMicrotasks();
      expect(env.state.hasAlerts, isFalse);
      env.container.read(settingsProvider.notifier).update((s) => s.copyWith(gustWarnKn: 12));
      expect(env.state.hasAlerts, isTrue);
    });
  });

  test('a throwing service never escapes', () {
    run((async, env) {
      env.service.respond = (_) => throw StateError('boom');
      env.startWatch();
      async.flushMicrotasks();
      expect(env.state.error, contains('boom'));
      expect(env.state.loading, isFalse);
    });
  });
}
