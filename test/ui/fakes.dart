import 'dart:async';

import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/app/providers.dart';
import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/services/alarm/alarm_output.dart';
import 'package:anchor_alarm/services/alarm/notification_service.dart';
import 'package:anchor_alarm/services/battery/battery_monitor.dart';
import 'package:anchor_alarm/services/failsafe/failsafe.dart';
import 'package:anchor_alarm/services/heading/heading_source.dart';
import 'package:anchor_alarm/services/location/location_source.dart';
import 'package:anchor_alarm/services/map/depth_service.dart';
import 'package:anchor_alarm/services/map/tile_layer_spec.dart';
import 'package:anchor_alarm/services/storage/repositories.dart';
import 'package:anchor_alarm/services/weather/weather_service.dart';
import 'package:anchor_alarm/ui/map/tile_layers.dart';
import 'package:anchor_alarm/ui/ui_providers.dart';
import 'package:anchor_alarm/ui/widgets/permission_notice.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:latlong2/latlong.dart';

class FakeLocationSource implements LocationSource {
  final _ctrl = StreamController<PositionFix>.broadcast();
  LocationPermissionResult permission = LocationPermissionResult.always;

  void emit(PositionFix fix) => _ctrl.add(fix);

  @override
  String get label => 'Fake GPS';

  @override
  Future<LocationPermissionResult> requestPermission({bool background = false}) async =>
      permission;

  @override
  Stream<PositionFix> watch({bool background = false}) => _ctrl.stream;

  @override
  Future<PositionFix?> currentFix() async => null;
}

class FakeHeadingSource implements HeadingSource {
  FakeHeadingSource([this.value]);
  final double? value;

  @override
  Future<bool> get available async => value != null;

  @override
  Stream<double?> get heading => Stream.value(value);
}

class FakeAlarmOutput implements AlarmOutput {
  int starts = 0;
  int stops = 0;
  bool _ringing = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> startAlarm({required String sound, required bool vibrate}) async {
    starts++;
    _ringing = true;
  }

  @override
  Future<void> stopAlarm() async {
    stops++;
    _ringing = false;
  }

  @override
  Future<void> chime({required bool vibrate}) async {}

  @override
  bool get isRinging => _ringing;
}

class FakeNotificationService implements NotificationService {
  final _actions = StreamController<String>.broadcast();

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showAlert({
    required AlertReason reason,
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> showInfo({required String title, required String body}) async {}
  @override
  Future<void> cancelAlert(AlertReason reason) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Stream<String> get actions => _actions.stream;
}

class FakeBatteryMonitor implements BatteryMonitor {
  @override
  Stream<BatteryReading> get readings => const Stream.empty();
}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this.settings = const AppSettings()]);
  AppSettings settings;
  List<AlarmProfile> custom = [];

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings s) async => settings = s;
  @override
  Future<List<AlarmProfile>> loadCustomProfiles() async => custom;
  @override
  Future<void> saveCustomProfiles(List<AlarmProfile> profiles) async => custom = profiles;
}

class InMemorySessionRepository implements SessionRepository {
  InMemorySessionRepository([List<AnchorSession> sessions = const []])
      : _sessions = {for (final s in sessions) s.id: s};

  final Map<String, AnchorSession> _sessions;
  final Map<String, List<TrackPoint>> tracks = {};

  @override
  Future<void> save(AnchorSession session) async => _sessions[session.id] = session;
  @override
  Future<AnchorSession?> loadActive() async =>
      _sessions.values.where((s) => s.isActive).firstOrNull;
  @override
  Future<List<AnchorSession>> history() async =>
      _sessions.values.where((s) => !s.isActive).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  @override
  Future<AnchorSession?> get(String id) async => _sessions[id];
  @override
  Future<void> delete(String id) async {
    _sessions.remove(id);
    tracks.remove(id);
  }

  @override
  Future<void> appendTrack(String sessionId, List<TrackPoint> points) async =>
      (tracks[sessionId] ??= []).addAll(points);
  @override
  Future<List<TrackPoint>> track(String sessionId) async => tracks[sessionId] ?? const [];
}

/// Returns a transparent tile without touching the network.
class TransparentTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(TileProvider.transparentImage);
}

/// A [WatchController] with a fixed state; records user actions.
class FixedWatchController extends WatchController {
  FixedWatchController(this.initial);
  final WatchViewState initial;
  int acknowledged = 0;
  final List<double> radii = [];

  @override
  WatchViewState build() => initial;

  @override
  Future<void> acknowledge() async => acknowledged++;

  @override
  void setRadius(double radiusM) => radii.add(radiusM);

  @override
  Future<void> restore() async {}

  @override
  Future<LocationPermissionResult> requestPermission({bool background = false}) async =>
      LocationPermissionResult.always;
}

/// Charted depth without network: returns [sample] and records the queries.
class FakeDepthService extends DepthService {
  FakeDepthService({this.sample});
  DepthSample? sample;
  final queries = <LatLng>[];

  @override
  Future<DepthSample?> depthAt(LatLng p) async {
    queries.add(p);
    return sample;
  }
}

/// Test settings: no network tiles, onboarding done.
const testSettings = AppSettings(
  baseMap: BaseMap.none,
  seamarks: false,
  onboardingDone: true,
);

class TestEnv {
  TestEnv({
    AppSettings settings = testSettings,
    List<AnchorSession> sessions = const [],
  })  : settingsRepo = InMemorySettingsRepository(settings),
        sessionRepo = InMemorySessionRepository(sessions),
        initialSettings = settings;

  final location = FakeLocationSource();
  final alarm = FakeAlarmOutput();
  final notifications = FakeNotificationService();
  final InMemorySettingsRepository settingsRepo;
  final InMemorySessionRepository sessionRepo;
  final AppSettings initialSettings;
  final wakeCalls = <bool>[];
  final depth = FakeDepthService();
  final weather = FakeWeatherService();
  final weatherRepo = MemoryWeatherRepository();

  List<Override> overrides({WatchController Function()? controller}) => [
        initialSettingsProvider.overrideWithValue(initialSettings),
        deviceLocationProvider.overrideWithValue(location),
        deviceHeadingProvider.overrideWithValue(FakeHeadingSource()),
        alarmOutputProvider.overrideWithValue(alarm),
        notificationServiceProvider.overrideWithValue(notifications),
        batteryMonitorProvider.overrideWithValue(FakeBatteryMonitor()),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        sessionRepositoryProvider.overrideWithValue(sessionRepo),
        tileProviderFactoryProvider
            .overrideWithValue((TileLayerSpec _) => TransparentTileProvider()),
        screenWakeProvider.overrideWithValue((on) async => wakeCalls.add(on)),
        failsafeProvider.overrideWithValue(const NoopFailsafe()),
        tileCacheSizeProvider.overrideWith((ref) async => 2 * 1024 * 1024),
        openSettingsProvider.overrideWithValue(({bool location = false}) async {}),
        depthServiceProvider.overrideWithValue(depth),
        weatherServiceProvider.overrideWithValue(weather),
        weatherRepositoryProvider.overrideWithValue(weatherRepo),
        if (controller != null) watchControllerProvider.overrideWith(controller),
      ];
}

/// Weather without network: returns [result] (offline by default) and
/// records the queried positions.
class FakeWeatherService extends WeatherService {
  FakeWeatherService({this.result = const WeatherError('offline'), this.respond});
  WeatherResult result;

  /// When set, answers instead of [result] (e.g. a forecast fetched "now").
  WeatherResult Function(LatLng p)? respond;
  final queries = <LatLng>[];

  @override
  Future<WeatherResult> fetch(LatLng p) async {
    queries.add(p);
    return respond?.call(p) ?? result;
  }
}
