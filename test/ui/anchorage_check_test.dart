import 'package:anchor_alarm/app/anchorage_assistant.dart';
import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/water_mask.dart';
import 'package:anchor_alarm/domain/weather.dart';
import 'package:anchor_alarm/services/map/anchorage_service.dart';
import 'package:anchor_alarm/services/weather/weather_service.dart';
import 'package:anchor_alarm/ui/app.dart';
import 'package:anchor_alarm/ui/screens/drop_anchor/drop_anchor_panel.dart';
import 'package:anchor_alarm/ui/widgets/anchorage_check.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes.dart';

const boat = LatLng(43.1638, 16.3972);

/// 9 km of 100 m pixels around [boat]: a bay open to the south.
WaterMask bayOpenSouth() {
  const px = 90, m = 100.0;
  final rows = [
    for (var y = 0; y < px; y++)
      String.fromCharCodes([
        for (var x = 0; x < px; x++)
          () {
            final e = -px * m / 2 + (x + 0.5) * m;
            final n = px * m / 2 - (y + 0.5) * m;
            return n > 300 || (e.abs() > 400 && n > -800) ? 0x23 : 0x2E;
          }(),
      ]),
  ];
  return WaterMask.fromRows(rows, centre: boat, metresPerPixel: m, source: 'EMODnet');
}

/// Southerly 18 kn for hours 3–6, light northerly otherwise.
Forecast southerlyLater(DateTime now) {
  final h0 = DateTime.utc(now.year, now.month, now.day, now.hour).toUtc();
  return Forecast(
    fetchedAt: now,
    location: boat,
    hourly: [
      for (var i = 0; i < 30; i++)
        WeatherConditions(
          time: h0.add(Duration(hours: i)),
          windKn: i >= 3 && i <= 6 ? 18 : 6,
          gustKn: i >= 3 && i <= 6 ? 24 : 9,
          windDirDeg: i >= 3 && i <= 6 ? 180 : 0,
        ),
    ],
  );
}

AnchorSession past(String id, {bool drag = false}) => AnchorSession(
      id: id,
      anchor: boat,
      radiusM: 40,
      initialRadiusM: 40,
      profile: AlarmProfile.builtIns[1],
      startedAt: DateTime.utc(2026, 8, 1),
      endedAt: DateTime.utc(2026, 8, 2),
      alerts: [if (drag) AlertEvent(reason: AlertReason.drag, time: DateTime.utc(2026, 8, 1, 3))],
    );

Future<ProviderContainer> openDropAnchor(WidgetTester tester, TestEnv env) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: env.overrides(), child: const AnchorAlarmApp()));
  await tester.pump();
  env.location.emit(PositionFix(position: boat, accuracyM: 4, time: DateTime.now()));
  await tester.pump();
  await tester.tap(find.text('Drop anchor'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(AnchorAlarmApp)));
}

Finder get panelScroll => find
    .descendant(of: find.byType(DropAnchorPanel), matching: find.byType(Scrollable))
    .first;

void main() {
  testWidgets('Anchorage check: collapsed verdict, expands to shelter, forecast, log, nearby',
      (tester) async {
    final env = TestEnv(sessions: [past('a'), past('b')]);
    env.landMask.mask = bayOpenSouth();
    env.anchorages.result = [
      NearbyAnchorage(
        position: const LatLng(43.1594, 16.3921),
        kind: AnchorageKind.anchorage,
        distanceM: 640,
        name: 'Vinogradišće',
      ),
    ];
    env.weather.respond = (_) => WeatherOk(southerlyLater(clock.now()));
    final container = await openDropAnchor(tester, env);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('anchorageCheck')), 100,
        scrollable: panelScroll);
    await tester.pump();
    expect(env.landMask.queries, isNotEmpty);
    // Collapsed: one line.
    expect(find.textContaining('Exposed to S gusts 24 kn at'), findsOneWidget);
    expect(find.byKey(const ValueKey('shelterText')), findsNothing);
    expect(container.read(anchorageCheckProvider).expanded, isFalse);

    await tester.tap(find.byKey(const ValueKey('anchorageCheckHeader')));
    await tester.pump();
    expect(container.read(anchorageCheckProvider).expanded, isTrue);
    expect(find.textContaining('Sheltered from', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Exposed to SSE–SSW', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('consider another anchorage', skipOffstage: false), findsOneWidget);
    expect(find.byKey(const ValueKey('exposureTimeline'), skipOffstage: false), findsOneWidget);
    expect(find.textContaining('→ scope', skipOffstage: false), findsOneWidget);
    expect(find.text('You anchored here 2× before, no drag alarms', skipOffstage: false),
        findsOneWidget);
    expect(find.text('Nearby: Vinogradišće (640 m)', skipOffstage: false), findsOneWidget);

    // The swing preview exists for the draft anchor.
    expect(container.read(swingPreviewProvider), isNotNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Anchorage check without land data or forecast says so', (tester) async {
    final env = TestEnv();
    final container = await openDropAnchor(tester, env);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('anchorageCheck')), 100,
        scrollable: panelScroll);
    expect(find.text('No shelter or forecast data'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('anchorageCheckHeader')));
    await tester.pump();
    expect(find.textContaining('No land data for this spot', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('No forecast yet', skipOffstage: false), findsOneWidget);
    expect(find.byKey(const ValueKey('nearbyUnavailable'), skipOffstage: false), findsOneWidget);
    expect(container.read(swingPreviewProvider), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('While watching: "Check this anchorage" from the adjust sheet', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv(sessions: [past('a', drag: true)]);
    env.landMask.mask = bayOpenSouth();
    final session = AnchorSession(
      id: 's1',
      anchor: boat,
      radiusM: 45,
      initialRadiusM: 45,
      profile: AlarmProfile.builtIns[1],
      startedAt: DateTime(2026, 10, 20, 22),
      rodeM: 30,
      depthM: 5,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(
          controller: () => FixedWatchController(WatchViewState(session: session))),
      child: const AnchorAlarmApp(),
    ));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(AnchorAlarmApp)));

    await tester.tap(find.byTooltip('Adjust radius or profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkAnchorage')));
    await tester.pumpAndSettle();
    expect(find.byType(AnchorageCheckCard), findsOneWidget);
    expect(find.text('Open to SSE–SSW (no forecast)'), findsOneWidget);
    expect(find.text('You anchored here 1× before, drag alarm once', skipOffstage: false),
        findsOneWidget);
    expect(find.textContaining('scope 5.0:1', skipOffstage: false), findsOneWidget);
    expect(container.read(anchorageCheckProvider).expanded, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
