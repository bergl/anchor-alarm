import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/watch_engine.dart';
import 'package:anchor_alarm/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes.dart';

const anchor = LatLng(43.1633, 16.3972);
const boat = LatLng(43.1638, 16.3972);

AnchorSession session() => AnchorSession(
      id: 's1',
      anchor: anchor,
      radiusM: 45,
      initialRadiusM: 45,
      profile: AlarmProfile.builtIns[1],
      startedAt: DateTime(2026, 10, 20, 22),
    );

WatchViewState watching({
  required WatchState state,
  Set<AlertReason> reasons = const {},
  bool ringing = false,
  DateTime? snoozedUntil,
}) =>
    WatchViewState(
      session: session(),
      sourceLabel: 'Phone GPS',
      snapshot: WatchSnapshot(
        time: DateTime(2026, 10, 20, 23),
        state: state,
        reasons: reasons,
        ringing: ringing,
        radiusM: 45,
        warningRadiusM: 36,
        maxDistanceM: 61,
        distanceM: 58,
        bearingFromAnchorDeg: 0,
        position: boat,
        accuracyM: 4,
        snoozedUntil: snoozedUntil,
      ),
    );

Future<void> pumpApp(WidgetTester tester, TestEnv env,
    {WatchController Function()? controller}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: env.overrides(controller: controller),
    child: const AnchorAlarmApp(),
  ));
  await tester.pump();
}

/// Disposes the ProviderScope so the controller's timers are cancelled.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('idle map screen shows the Drop anchor button', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env);

    expect(find.text('Drop anchor'), findsOneWidget);
    expect(find.text('Waiting for GPS…'), findsOneWidget);

    await tester.pump();
    await tester.pump();
    env.location.emit(PositionFix(position: boat, accuracyM: 4, time: DateTime.now()));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Fake GPS'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('first launch shows the intro', (tester) async {
    final env = TestEnv(settings: testSettings.copyWith(onboardingDone: false));
    await pumpApp(tester, env);
    expect(find.text('Sleep while the phone keeps watch'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Drop anchor'), findsOneWidget);
    expect(env.settingsRepo.settings.onboardingDone, isTrue);
    await unmount(tester);
  });

  testWidgets('drop anchor flow previews a draft and starts the watch', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env);
    env.location.emit(PositionFix(position: boat, accuracyM: 4, time: DateTime.now()));
    await tester.pump();

    await tester.tap(find.text('Drop anchor'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Boat has settled'), findsOneWidget);
    expect(find.text('Start anchor watch'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(AnchorAlarmApp)));
    final draft = container.read(watchControllerProvider).draft;
    expect(draft, isNotNull);
    // 30 m rode, 5 m depth, 12 m boat, 5 m margin → √(900−25)+17 ≈ 46.6 m.
    expect(draft!.radiusM, closeTo(46.6, 0.1));

    await tester.tap(find.text('Start anchor watch'));
    await tester.pump();
    await tester.pump();
    expect(container.read(watchControllerProvider).watching, isTrue);
    expect(find.text('Drop anchor'), findsNothing);
    await unmount(tester);
  });

  testWidgets('HUD shows ALARM and the overlay offers SILENCE when ringing',
      (tester) async {
    final env = TestEnv();
    final fixed = FixedWatchController(watching(
      state: WatchState.alarm,
      reasons: {AlertReason.drag},
      ringing: true,
    ));
    await pumpApp(tester, env, controller: () => fixed);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ALARM'), findsOneWidget);
    expect(find.text('ANCHOR DRAGGING'), findsOneWidget);
    expect(find.text('SILENCE'), findsOneWidget);
    expect(find.text('Re-anchor here'), findsOneWidget);

    await tester.tap(find.text('SILENCE'));
    await tester.pump();
    expect(fixed.acknowledged, 1);
    await unmount(tester);
  });

  testWidgets('HUD shows SAFE with distance and radius', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env,
        controller: () => FixedWatchController(watching(state: WatchState.safe)));

    expect(find.text('SAFE'), findsOneWidget);
    expect(find.text('SILENCE'), findsNothing);
    expect(find.text('Phone GPS'), findsOneWidget);
    expect(find.byTooltip('Stop watch'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('snoozed alarm shows a countdown chip', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env,
        controller: () => FixedWatchController(watching(
              state: WatchState.alarm,
              reasons: {AlertReason.drag},
              snoozedUntil: DateTime(2026, 10, 20, 23, 1, 30),
            )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Snoozed 1:30'), findsOneWidget);
    expect(find.text('SILENCE'), findsNothing);
    await unmount(tester);
  });

  testWidgets('keeps the screen on while watching when enabled', (tester) async {
    final env = TestEnv(settings: testSettings.copyWith(keepScreenOn: true));
    await pumpApp(tester, env,
        controller: () => FixedWatchController(watching(state: WatchState.safe)));
    await tester.pump();
    expect(env.wakeCalls, [true]);
    await unmount(tester);
  });
}
