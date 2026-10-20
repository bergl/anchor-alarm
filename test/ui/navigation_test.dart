import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes.dart';
import 'map_screen_test.dart' show pumpApp, unmount;

void main() {
  testWidgets('History → detail → back → back returns to the map', (tester) async {
    final env = TestEnv(sessions: [
      AnchorSession(
        id: 'a',
        name: 'Palmižana',
        anchor: const LatLng(43.1633, 16.3972),
        radiusM: 40,
        initialRadiusM: 40,
        profile: AlarmProfile.builtIns[1],
        startedAt: DateTime(2026, 8, 1, 20),
        endedAt: DateTime(2026, 8, 2, 7),
      ),
    ]);
    await pumpApp(tester, env,
        controller: () => FixedWatchController(const WatchViewState()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Palmižana'));
    await tester.pumpAndSettle();
    expect(find.text('Alerts'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Alerts'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Drop anchor'), findsOneWidget);
    await unmount(tester);
  });
}
