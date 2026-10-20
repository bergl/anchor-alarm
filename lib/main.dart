import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/watch_controller.dart';
import 'services/platform_services.dart';
import 'services/storage/app_database.dart';
import 'ui/app.dart';

/// Composition root: opens storage, creates the platform services, wires the
/// providers and resumes an interrupted anchor watch.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await openAppDatabase();
  final settings = await database.settings.load();
  final customProfiles = await database.settings.loadCustomProfiles();

  final services = createPlatformServices();
  await services.init();

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      settingsRepositoryProvider.overrideWithValue(database.settings),
      sessionRepositoryProvider.overrideWithValue(database.sessions),
      initialSettingsProvider.overrideWithValue(settings),
      initialCustomProfilesProvider.overrideWithValue(customProfiles),
      deviceLocationProvider.overrideWithValue(services.location),
      deviceHeadingProvider.overrideWithValue(services.heading),
      alarmOutputProvider.overrideWithValue(services.alarm),
      notificationServiceProvider.overrideWithValue(services.notifications),
      batteryMonitorProvider.overrideWithValue(services.battery),
      failsafeProvider.overrideWithValue(services.failsafe),
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
