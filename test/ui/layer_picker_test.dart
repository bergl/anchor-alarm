import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('Layers button opens the picker and writes the settings', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv();
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(),
      child: const AnchorAlarmApp(),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Layers'));
    await tester.pumpAndSettle();
    expect(find.text('Map layers'), findsOneWidget);

    await tester.tap(find.text('Depth relief'));
    await tester.pump();
    await tester.tap(find.text('EMODnet'));
    await tester.pump();
    await tester.tap(find.text('Seamarks (OpenSeaMap)'));
    await tester.pump();

    final s = env.settingsRepo.settings;
    expect(s.baseMap, BaseMap.bathymetry);
    expect(s.depthLayer, DepthLayer.emodnet);
    expect(s.seamarks, isTrue); // testSettings start with seamarks off
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
