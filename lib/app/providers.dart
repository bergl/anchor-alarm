import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../services/alarm/alarm_output.dart';
import '../services/alarm/notification_service.dart';
import '../services/battery/battery_monitor.dart';
import '../services/failsafe/failsafe.dart';
import '../services/heading/heading_source.dart';
import '../services/location/location_source.dart';
import '../services/location/simulated_location_source.dart';
import '../services/map/tile_cache.dart';
import '../services/remote/remote_sync.dart';
import '../services/storage/app_database.dart';
import '../services/storage/repositories.dart';
import 'app_settings.dart';

// Platform services. Overridden in main() (and in tests) with real implementations.
final deviceLocationProvider =
    Provider<LocationSource>((ref) => throw UnimplementedError('override'));
final deviceHeadingProvider =
    Provider<HeadingSource>((ref) => throw UnimplementedError('override'));
final alarmOutputProvider =
    Provider<AlarmOutput>((ref) => throw UnimplementedError('override'));
final notificationServiceProvider =
    Provider<NotificationService>((ref) => throw UnimplementedError('override'));
final batteryMonitorProvider =
    Provider<BatteryMonitor>((ref) => throw UnimplementedError('override'));
final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => throw UnimplementedError('override'));
final sessionRepositoryProvider =
    Provider<SessionRepository>((ref) => throw UnimplementedError('override'));
final remoteSyncProvider = Provider<RemoteSync>((ref) => const NoopRemoteSync());

/// Settings and custom profiles loaded before runApp().
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());
final initialCustomProfilesProvider = Provider<List<AlarmProfile>>((ref) => const []);

/// Single simulator instance shared by location and heading.
final simulatorProvider =
    Provider<SimulatedLocationSource>((ref) => SimulatedLocationSource());

/// The location source in use: device GPS or the simulator.
final locationSourceProvider = Provider<LocationSource>((ref) {
  final sim = ref.watch(settingsProvider.select((s) => s.useSimulator));
  return sim ? ref.watch(simulatorProvider) : ref.watch(deviceLocationProvider);
});

final headingSourceProvider = Provider<HeadingSource>((ref) {
  final sim = ref.watch(settingsProvider.select((s) => s.useSimulator));
  return sim ? ref.watch(simulatorProvider) : ref.watch(deviceHeadingProvider);
});

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    ref.read(settingsRepositoryProvider).save(state);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Built-in profiles followed by the user's custom profiles.
class ProfilesController extends Notifier<List<AlarmProfile>> {
  @override
  List<AlarmProfile> build() =>
      [...AlarmProfile.builtIns, ...ref.read(initialCustomProfilesProvider)];

  /// Adds or replaces a custom profile. Built-ins are saved as a copy.
  void upsert(AlarmProfile p) {
    final custom = state.where((x) => !x.builtIn).toList();
    final i = custom.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      custom[i] = p;
    } else {
      custom.add(p);
    }
    state = [...AlarmProfile.builtIns, ...custom];
    ref.read(settingsRepositoryProvider).saveCustomProfiles(custom);
  }

  void remove(String id) {
    final custom = state.where((x) => !x.builtIn && x.id != id).toList();
    state = [...AlarmProfile.builtIns, ...custom];
    ref.read(settingsRepositoryProvider).saveCustomProfiles(custom);
  }
}

final profilesProvider =
    NotifierProvider<ProfilesController, List<AlarmProfile>>(ProfilesController.new);

final activeProfileProvider = Provider<AlarmProfile>((ref) {
  final id = ref.watch(settingsProvider.select((s) => s.activeProfileId));
  final all = ref.watch(profilesProvider);
  return all.firstWhere((p) => p.id == id, orElse: () => AlarmProfile.builtIns[1]);
});

// ---- Storage & offline map (added by the storage/map integration) --------

/// The opened local database. Overridden in main() with the instance from
/// `openAppDatabase()`; [settingsRepositoryProvider] and
/// [sessionRepositoryProvider] are overridden with its repositories.
final appDatabaseProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError('override'));

/// Persistent tile cache (disk on mobile, no-op on web).
///
/// Create one `CachingTileProvider(layer: spec, cache: ref.watch(tileCacheProvider))`
/// per `TileLayer` — flutter_map disposes the tile provider with its layer,
/// so tile providers must not be shared.
final tileCacheProvider = Provider<TileCache>((ref) {
  final cache = TileCache();
  ref.onDispose(cache.close);
  return cache;
});

/// "Download this area" for offline use (unsupported on web, see
/// `TileDownloader.supported`).
final tileDownloaderProvider =
    Provider<TileDownloader>((ref) => TileDownloader(ref.watch(tileCacheProvider)));

/// Platform fail-safe (Android boot receiver etc.). Overridden in main();
/// main keeps it informed via `setWatchActive` whenever watching changes.
final failsafeProvider =
    Provider<Failsafe>((ref) => throw UnimplementedError('override'));
