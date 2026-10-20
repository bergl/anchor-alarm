import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/weather.dart';
import 'package:anchor_alarm/services/weather/weather_service.dart';
import 'package:anchor_alarm/ui/screens/settings_screen.dart';
import 'package:anchor_alarm/ui/theme/app_theme.dart';
import 'package:anchor_alarm/ui/widgets/status_hud.dart';
import 'package:anchor_alarm/ui/widgets/weather_line.dart';
import 'package:anchor_alarm/ui/widgets/weather_sheet.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes.dart';

const anchor = LatLng(43.1633, 16.3972);

WatchViewState watchingState() => WatchViewState(
      session: AnchorSession(
        id: 's1',
        anchor: anchor,
        radiusM: 45,
        initialRadiusM: 45,
        profile: AlarmProfile.builtIns[1],
        startedAt: DateTime(2026, 10, 20, 22),
      ),
    );

/// NW 12 kn gusting 18 now; gusts to [maxGust] in 5 h.
Forecast forecast(DateTime now, {double maxGust = 30}) {
  final n = now.toUtc();
  final start = DateTime.utc(n.year, n.month, n.day, n.hour);
  return Forecast(
    fetchedAt: n,
    location: anchor,
    current: WeatherConditions(time: n, windKn: 12, gustKn: 18, windDirDeg: 315),
    hasMarine: true,
    hourly: [
      for (var i = 0; i < 30; i++)
        WeatherConditions(
          time: start.add(Duration(hours: i)),
          windKn: 12,
          gustKn: i == 5 ? maxGust : 18,
          windDirDeg: 315,
          pressureHpa: 1015,
          waveHeightM: 0.6,
        ),
    ],
  );
}

Future<void> pumpHud(WidgetTester tester, TestEnv env, {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: env.overrides(controller: () => FixedWatchController(watchingState())),
    child: MaterialApp(
      theme: theme ?? AppTheme.day(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: StatusHud(onDropAnchor: () {}, onAdjust: () {}, onStop: () {}),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('HUD weather line with alert icon; tap opens the sheet', (tester) async {
    final env = TestEnv();
    env.weather.respond = (_) => WeatherOk(forecast(clock.now()));
    await pumpHud(tester, env);

    expect(env.weather.queries, [anchor], reason: 'fetched for the anchor on watch start');
    expect(find.textContaining('Wind 12 kn NW · gusts 18 · max 30 kn'), findsOneWidget);
    expect(find.byKey(const ValueKey('weatherAlertIcon')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('weatherLine')));
    await tester.pumpAndSettle();
    expect(find.text('Weather'), findsOneWidget);
    expect(find.text('Strong gusts forecast'), findsOneWidget);
    expect(find.byKey(const ValueKey('windChart')), findsOneWidget);
    expect(find.textContaining('Forecast from'), findsOneWidget);
    expect(find.textContaining('just now'), findsOneWidget);
    await tester.scrollUntilVisible(find.text(WeatherService.attribution), 300,
        scrollable: find
            .descendant(of: find.byType(WeatherSheet), matching: find.byType(Scrollable))
            .first);
    expect(find.text(WeatherService.attribution), findsOneWidget);
    await tester.scrollUntilVisible(find.byTooltip('Refresh forecast'), -300,
        scrollable: find
            .descendant(of: find.byType(WeatherSheet), matching: find.byType(Scrollable))
            .first);

    // Manual refresh.
    await tester.tap(find.byTooltip('Refresh forecast'));
    await tester.pumpAndSettle();
    expect(env.weather.queries, hasLength(2));
    await unmount(tester);
  });

  testWidgets('no alert → plain icon; night theme renders', (tester) async {
    final env = TestEnv();
    env.weather.respond = (_) => WeatherOk(forecast(clock.now(), maxGust: 18));
    await pumpHud(tester, env, theme: AppTheme.night());
    expect(find.text('Wind 12 kn NW · gusts 18'), findsOneWidget);
    expect(find.byKey(const ValueKey('weatherIcon')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('weatherLine')));
    await tester.pumpAndSettle();
    expect(find.text('No forecast alerts for the next 24 h.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('offline: cached forecast with its age', (tester) async {
    final env = TestEnv(); // weather service is offline by default
    env.weatherRepo.forecast =
        forecast(clock.now().subtract(const Duration(hours: 4)), maxGust: 18);
    await pumpHud(tester, env);
    expect(find.textContaining('· 4 h old'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('weatherLine')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline — showing the last forecast'), findsOneWidget);
    expect(find.textContaining('4 h ago'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('no data at all', (tester) async {
    final env = TestEnv();
    await pumpHud(tester, env);
    expect(find.text('Weather unavailable'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('drop-anchor outlook hint', (tester) async {
    final env = TestEnv();
    env.weather.respond = (_) => WeatherOk(forecast(clock.now()));
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(
          controller: () => FixedWatchController(WatchViewState(
              fix: PositionFix(position: anchor, accuracyM: 4, time: DateTime.now())))),
      child: const MaterialApp(home: Scaffold(body: WeatherOutlookHint())),
    ));
    await tester.pump();
    await tester.pump();
    expect(env.weather.queries, [anchor]);
    expect(find.text('Next 12 h: wind NW up to 12 kn, gusts to 30 kn, waves to 0.6 m'),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('settings: weather alerts and thresholds', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv();
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(controller: () => FixedWatchController(const WatchViewState())),
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();

    final toggle = find.text('Forecast alerts while watching');
    await tester.scrollUntilVisible(toggle, 200);
    await tester.pump();
    expect(find.text('25 kn'), findsOneWidget);
    expect(find.text('20 kn'), findsOneWidget);
    expect(find.text('1.5 m'), findsOneWidget);

    await tester.tap(find.text('Gusts over'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(env.settingsRepo.settings.gustWarnKn, 30);
    expect(find.text('30 kn'), findsOneWidget);

    await tester.tap(find.text('Waves over'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(env.settingsRepo.settings.waveWarnM, 2.5);

    await tester.tap(toggle);
    await tester.pump();
    expect(env.settingsRepo.settings.weatherAlerts, isFalse);
  });
}
