import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/remote_controllers.dart';
import 'app/watch_controller.dart';
import 'services/platform_services.dart';
import 'services/remote/firebase_bootstrap.dart';
import 'services/remote/firebase_config.dart';
import 'services/remote/remote_models.dart';
import 'services/storage/app_database.dart';
import 'ui/app.dart';

/// Composition root: opens storage, creates the platform services, wires the
/// providers and resumes an interrupted anchor watch.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Storage can be unavailable (private browsing, a sandboxed web preview).
  // The anchor watch must still start, so fall back to memory: nothing is
  // remembered across restarts, but every alarm works.
  AppDatabase database;
  try {
    database = await openAppDatabase().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Storage unavailable, using memory: $e');
    database = await openAppDatabase(inMemory: true);
  }
  var settings = await database.settings.load();
  // Demo builds (`--dart-define=DEMO=true`, e.g. the hosted web preview) start
  // with the GPS simulator so the app can be tried without a boat.
  if (const bool.fromEnvironment('DEMO') && !settings.onboardingDone) {
    settings = settings.copyWith(useSimulator: true);
  }
  final customProfiles = await database.settings.loadCustomProfiles();

  final services = createPlatformServices();
  await services.init();

  // Remote monitoring (Firebase) only in builds with a Firebase
  // configuration (--dart-define-from-file=firebase.json); null otherwise.
  final remote = await startFirebaseRemote(
    config: FirebaseConfig.fromEnvironment(),
    database: database.db,
  );
  // Web: a share link (`#join=<watchId>.<key>`) opens "Monitor a boat".
  final fragment = kIsWeb ? Uri.base.fragment : '';
  final joinLink = fragment.contains('join=') ? ShareLink.parse(fragment) : null;

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      settingsRepositoryProvider.overrideWithValue(database.settings),
      sessionRepositoryProvider.overrideWithValue(database.sessions),
      weatherRepositoryProvider.overrideWithValue(database.weather),
      initialSettingsProvider.overrideWithValue(settings),
      initialCustomProfilesProvider.overrideWithValue(customProfiles),
      deviceLocationProvider.overrideWithValue(services.location),
      deviceHeadingProvider.overrideWithValue(services.heading),
      alarmOutputProvider.overrideWithValue(services.alarm),
      notificationServiceProvider.overrideWithValue(services.notifications),
      batteryMonitorProvider.overrideWithValue(services.battery),
      failsafeProvider.overrideWithValue(services.failsafe),
      if (remote != null) ...[
        remoteServicesProvider.overrideWithValue(remote),
        remoteSyncProvider.overrideWithValue(remote.sync),
      ],
      initialJoinLinkProvider.overrideWithValue(joinLink),
    ],
  );

  runApp(UncontrolledProviderScope(
    container: container,
    child: const AnchorAlarmApp(),
  ));

  // Resume a watch that was active when the app was killed or the phone
  // rebooted, then keep the fail-safe (e.g. Android boot receiver) informed
  // whether a watch is active.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await container.read(watchControllerProvider.notifier).restore();
    } finally {
      final watching = container.read(watchControllerProvider).watching;
      unawaited(services.failsafe.setWatchActive(watching));
      container.listen<bool>(
        watchControllerProvider.select((s) => s.watching),
        (prev, next) {
          if (prev != next) unawaited(services.failsafe.setWatchActive(next));
        },
      );
    }
  });
}
