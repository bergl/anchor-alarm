import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/watch_engine.dart';
import 'package:anchor_alarm/services/remote/firebase_config.dart';
import 'package:anchor_alarm/services/remote/remote_models.dart';
import 'package:anchor_alarm/services/remote/remote_store.dart';
import 'package:anchor_alarm/ui/remote/monitor_screen.dart';
import 'package:anchor_alarm/ui/app.dart';
import 'package:anchor_alarm/ui/remote/share_watch_sheet.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../ui/fakes.dart';
import '../ui/map_screen_test.dart' show pumpApp, unmount;
import 'remote_fakes.dart';

const watchId = 'AbCdEfGhIj0123456789';
const key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const anchor = LatLng(43.5, 16.4);

RemoteWatch remote({
  DateTime? updatedAt,
  bool ringing = false,
  Set<AlertReason> reasons = const {},
  WatchState state = WatchState.safe,
  DateTime? endedAt,
}) =>
    RemoteWatch(
      id: watchId,
      boatName: 'Kestrel',
      anchor: anchor,
      radiusM: 50,
      warningRadiusM: 45,
      boat: const LatLng(43.5003, 16.4),
      accuracyM: 5,
      state: state,
      reasons: reasons,
      ringing: ringing,
      distanceM: 33,
      updatedAt: updatedAt ?? clock.now(),
      endedAt: endedAt,
    );

Future<void> pumpScreen(WidgetTester tester, TestEnv env, RemoteTestEnv remoteEnv, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [...env.overrides(), ...remoteEnv.overrides],
    child: MaterialApp(home: screen),
  ));
  await tester.pump();
}

final monitoredKestrel = MonitoredBoat(watchId: watchId, shareKey: key, addedAt: DateTime(2026, 10, 20));

void main() {
  testWidgets('without Firebase config the remote entries explain why they are off', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env, controller: () => FixedWatchController(const WatchViewState()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Monitor a boat'), findsOneWidget);
    expect(find.text(remoteNotConfiguredMessage), findsOneWidget);
    await tester.tap(find.text('Monitor a boat'));
    await tester.pumpAndSettle();
    // Disabled: still on the drawer, no monitor screen.
    expect(find.text('Link or code'), findsNothing);
    await unmount(tester);
  });

  testWidgets('join: invalid code shows an error, a valid link joins with the push token', (tester) async {
    final env = TestEnv();
    final r = RemoteTestEnv();
    r.store.keys[watchId] = key;
    await pumpScreen(tester, env, r, const MonitorBoatsScreen());

    await tester.enterText(find.byType(TextField), 'not a code');
    await tester.tap(find.text('Start monitoring'));
    await tester.pumpAndSettle();
    expect(find.text('That is not a valid link or code.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '$watchId.${'Z' * 26}');
    await tester.tap(find.text('Start monitoring'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer valid'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'https://bergl.github.io/anchor-alarm/#join=$watchId.$key');
    await tester.tap(find.text('Start monitoring'));
    await tester.pump();
    await tester.pump();
    final (joinedId, joinedKey, tokens) = r.store.joins.single;
    expect((joinedId, joinedKey), (watchId, key));
    expect(tokens, ['push-token-1']);
    expect(r.local.monitored.single.watchId, watchId);
    r.store.emit(remote());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Kestrel'), findsWidgets);
    expect(find.text('SAFE'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('monitor screen: fresh → stale (amber) → lost contact (red)', (tester) async {
    final env = TestEnv();
    final r = RemoteTestEnv(monitored: [monitoredKestrel]);
    await pumpScreen(tester, env, r, const MonitorScreen(watchId: watchId));
    r.store.emit(remote(updatedAt: clock.now()));
    await tester.pump();
    await tester.pump();
    expect(find.text('updated just now'), findsOneWidget);
    expect(find.text('SAFE'), findsOneWidget);
    expect(find.textContaining('33 m from anchor'), findsOneWidget);

    await tester.pump(const Duration(seconds: 40));
    expect(find.text('updated 40 s ago'), findsOneWidget);
    final c = tester.widget<Text>(find.byKey(const Key('monitor-updated')));
    expect(c.style?.color, isNotNull, reason: 'amber when stale');

    await tester.pump(const Duration(minutes: 3));
    expect(find.text('LOST CONTACT'), findsOneWidget);
    expect(env.alarm.starts, 0, reason: 'lost contact chimes, it does not ring');
    await unmount(tester);
  });

  testWidgets('remote alarm rings here; "Silence (here)" silences only this device', (tester) async {
    final env = TestEnv();
    final r = RemoteTestEnv(monitored: [monitoredKestrel]);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...env.overrides(controller: () => FixedWatchController(const WatchViewState())),
        ...r.overrides,
      ],
      child: const AnchorAlarmApp(),
    ));
    await tester.pump();

    r.store.emit(remote());
    await tester.pump();
    expect(env.alarm.isRinging, isFalse);

    r.store.emit(remote(ringing: true, reasons: {AlertReason.drag}, state: WatchState.alarm));
    await tester.pump();
    await tester.pump();
    expect(env.alarm.isRinging, isTrue);
    expect(find.text('SILENCE (HERE)'), findsOneWidget);
    expect(find.text('ANCHOR DRAGGING'), findsOneWidget);

    await tester.tap(find.text('SILENCE (HERE)'));
    await tester.pump();
    expect(env.alarm.isRinging, isFalse);
    expect(find.text('SILENCE (HERE)'), findsNothing);
    expect(r.store.puts, isEmpty, reason: 'silencing here never writes to the boat');

    // Still the same alarm on the boat: stays silent here.
    await tester.pump(const Duration(seconds: 3));
    r.store.emit(remote(ringing: true, reasons: {AlertReason.drag}, state: WatchState.alarm));
    await tester.pump();
    expect(env.alarm.isRinging, isFalse);

    // A new alarm reason rings again.
    r.store.emit(remote(
        ringing: true, reasons: {AlertReason.drag, AlertReason.gpsLost}, state: WatchState.alarm));
    await tester.pump();
    await tester.pump();
    expect(env.alarm.isRinging, isTrue);

    // Silenced on the boat → stops here.
    r.store.emit(remote(reasons: {AlertReason.drag}, state: WatchState.alarm));
    await tester.pump();
    await tester.pump();
    expect(env.alarm.isRinging, isFalse);
    await unmount(tester);
  });

  testWidgets('ended watch and revoked access', (tester) async {
    final env = TestEnv();
    final r = RemoteTestEnv(monitored: [monitoredKestrel]);
    await pumpScreen(tester, env, r, const MonitorScreen(watchId: watchId));
    r.store.emit(remote(endedAt: clock.now()));
    await tester.pump();
    await tester.pump();
    expect(find.text('WATCH ENDED'), findsOneWidget);
    r.store.fail(watchId, const RemoteException(RemoteErrorKind.accessDenied));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('stopped sharing'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('share sheet: opt-in switch shows QR and link; stop sharing rotates', (tester) async {
    final env = TestEnv();
    final r = RemoteTestEnv();
    final session = AnchorSession(
      id: 's1',
      anchor: anchor,
      radiusM: 50,
      initialRadiusM: 50,
      profile: AlarmProfile.builtIns[1],
      startedAt: DateTime(2026, 10, 20, 12),
    );
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...env.overrides(
            controller: () => FixedWatchController(WatchViewState(
                  session: session,
                  snapshot: WatchSnapshot(
                    time: DateTime(2026, 10, 20, 12),
                    state: WatchState.safe,
                    reasons: const {},
                    ringing: false,
                    radiusM: 50,
                    warningRadiusM: 45,
                    maxDistanceM: 20,
                  ),
                ))),
        ...r.overrides,
      ],
      child: const MaterialApp(home: Scaffold(body: ShareWatchSheet())),
    ));
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(r.store.puts, isEmpty, reason: 'nothing uploaded before opting in');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    final rec = r.local.shareFor('s1')!;
    expect(find.text(rec.link.url), findsOneWidget);
    expect(rec.link.url, startsWith('https://bergl.github.io/anchor-alarm/#join='));
    expect(r.store.puts, hasLength(1));

    await tester.ensureVisible(find.text('Stop sharing'));
    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stop sharing'));
    await tester.pumpAndSettle();
    expect(r.store.stops.single.$1, rec.watchId);
    expect(find.byType(QrImageView), findsNothing);
    await unmount(tester);
  });
}
