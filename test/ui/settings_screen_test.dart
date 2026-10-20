import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('settings toggles the simulator and theme', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv();
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(controller: () => FixedWatchController(const WatchViewState())),
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();

    await tester.tap(find.text('Night (red)'));
    await tester.pump();
    expect(env.settingsRepo.settings.theme.name, 'night');

    await tester.scrollUntilVisible(find.text('Save chart around anchor automatically'), 200);
    await tester.ensureVisible(find.text('Save chart around anchor automatically'));
    await tester.pump();
    expect(find.textContaining('Downloads ~'), findsOneWidget);
    await tester.tap(find.text('Save chart around anchor automatically'));
    await tester.pump();
    expect(env.settingsRepo.settings.autoOfflineMap, isFalse);
    expect(find.text('Download chart around me now'), findsOneWidget);
    expect(find.text('Download this map area'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Use GPS simulator (demo)'), 200);
    await tester.ensureVisible(find.text('Use GPS simulator (demo)'));
    await tester.pump();
    await tester.tap(find.text('Use GPS simulator (demo)'));
    await tester.pump();
    expect(env.settingsRepo.settings.useSimulator, isTrue);
    expect(find.text('2.0 MB'), findsOneWidget);
  });

  testWidgets('test alarm starts and stops the alarm output', (tester) async {
    final env = TestEnv();
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(controller: () => FixedWatchController(const WatchViewState())),
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(env.alarm.starts, 1);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(env.alarm.stops, 1);
  });
}
