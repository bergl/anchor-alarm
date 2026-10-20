import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/services/map/depth_service.dart';
import 'package:anchor_alarm/ui/app.dart';
import 'package:anchor_alarm/ui/screens/drop_anchor/drop_anchor_model.dart';
import 'package:anchor_alarm/ui/screens/drop_anchor/drop_anchor_panel.dart';
import 'package:anchor_alarm/ui/screens/drop_anchor/drop_anchor_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes.dart';

const boat = LatLng(43.1638, 16.3972);
const emodnet8 = DepthSample(depthM: 8.43, source: 'EMODnet', resolution: '~115 m grid');
const gebco3 = DepthSample(depthM: 3, source: 'GEBCO', resolution: '~460 m grid');

void main() {
  group('DropAnchorForm.withChartedDepth', () {
    const form = DropAnchorForm(rodeM: 30, depthM: 5);

    test('prefills the depth (0.1 m) and keeps the hint', () {
      final f = form.withChartedDepth(emodnet8);
      expect(f.depthM, 8.4);
      expect(f.chartedDepth, emodnet8);
    });

    test('never overrides a user edit', () {
      final f = form.withUserDepth(12).withChartedDepth(emodnet8);
      expect(f.depthM, 12);
      expect(f.chartedDepth, emodnet8);
    });

    test('no prefill from coastline cells shallower than 1 m', () {
      const shallow = DepthSample(depthM: 0.5, source: 'EMODnet', resolution: '');
      expect(form.withChartedDepth(shallow).depthM, 5);
    });

    test('null clears the hint, keeps the depth', () {
      final f = form.withChartedDepth(emodnet8).withChartedDepth(null);
      expect(f.chartedDepth, isNull);
      expect(f.depthM, 8.4);
    });
  });

  testWidgets('Drop anchor panel prefills the charted depth unless edited',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv();
    env.depth.sample = emodnet8;
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(),
      child: const AnchorAlarmApp(),
    ));
    await tester.pump();
    env.location.emit(PositionFix(position: boat, accuracyM: 4, time: DateTime.now()));
    await tester.pump();

    await tester.tap(find.text('Drop anchor'));
    await tester.pump();
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(AnchorAlarmApp)));
    DropAnchorForm form() => container.read(dropAnchorFormProvider);
    final radiusBefore = container.read(watchControllerProvider).draft!.radiusM;

    // Debounced: nothing before 600 ms.
    await tester.pump(const Duration(milliseconds: 300));
    expect(env.depth.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(env.depth.queries, hasLength(1));
    expect(form().depthM, 8.4);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('chartedDepthCaption')), 100,
        scrollable: find
            .descendant(of: find.byType(DropAnchorPanel), matching: find.byType(Scrollable))
            .first);
    expect(find.text('Charted depth ≈ 8.4 m (EMODnet) — check your sounder'), findsOneWidget);
    // The radius suggestion follows the depth.
    expect(container.read(watchControllerProvider).draft!.radiusM, isNot(radiusBefore));

    // The user edits the depth; a later lookup must not override it.
    await tester.tap(find.byTooltip('More Depth'));
    await tester.pump();
    expect(form().depthM, 9);
    env.depth.sample = gebco3;
    container.read(dropAnchorFormProvider.notifier).placeOnMap(const LatLng(43.166, 16.40));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(env.depth.queries, hasLength(2));
    expect(form().depthM, 9);
    expect(form().chartedDepth, gebco3);
    expect(find.text('Charted depth ≈ 3.0 m (GEBCO) — check your sounder', skipOffstage: false),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
