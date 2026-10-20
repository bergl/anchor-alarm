import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/ui/screens/history_screen.dart';
import 'package:anchor_alarm/ui/screens/session_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes.dart';

AnchorSession finished(String id, String? name, DateTime start,
        {List<AlertEvent> alerts = const []}) =>
    AnchorSession(
      id: id,
      name: name,
      anchor: const LatLng(43.1633, 16.3972),
      radiusM: 40,
      initialRadiusM: 40,
      profile: AlarmProfile.builtIns[1],
      startedAt: start,
      endedAt: start.add(const Duration(hours: 9, minutes: 5)),
      maxDistanceM: 33,
      alerts: alerts,
    );

void main() {
  final sessions = [
    finished('a', 'Palmižana', DateTime(2026, 8, 1, 20)),
    finished('b', 'Stari Grad', DateTime(2026, 8, 3, 21), alerts: [
      AlertEvent(reason: AlertReason.drag, time: DateTime(2026, 8, 4, 3), distanceM: 52),
    ]),
  ];

  Future<TestEnv> pumpHistory(WidgetTester tester) async {
    final env = TestEnv(sessions: sessions);
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(controller: () => FixedWatchController(const WatchViewState())),
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pump();
    await tester.pump();
    return env;
  }

  testWidgets('history lists past sessions newest first', (tester) async {
    await pumpHistory(tester);
    expect(find.text('Palmižana'), findsOneWidget);
    expect(find.text('Stari Grad'), findsOneWidget);
    expect(find.textContaining('1 alarm'), findsOneWidget);
    expect(find.textContaining('no alarms'), findsOneWidget);
    expect(find.textContaining('9h 05m'), findsNWidgets(2));
    final first = tester.getTopLeft(find.text('Stari Grad')).dy;
    final second = tester.getTopLeft(find.text('Palmižana')).dy;
    expect(first, lessThan(second));
  });

  testWidgets('detail shows alerts and saves notes', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = await pumpHistory(tester);
    await tester.tap(find.text('Stari Grad'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.text('ANCHOR DRAGGING'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Notes (holding, bottom, wind…)'),
        'Good sand, 20 kn gusts');
    await tester.pump();
    await tester.ensureVisible(find.text('Save notes'));
    await tester.pump();
    await tester.tap(find.text('Save notes'));
    await tester.pump();
    await tester.pump();
    expect((await env.sessionRepo.get('b'))!.notes, 'Good sand, 20 kn gusts');
  });

  testWidgets('empty history shows a hint', (tester) async {
    final env = TestEnv();
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides(controller: () => FixedWatchController(const WatchViewState())),
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('No anchor watches yet'), findsOneWidget);
  });
}
