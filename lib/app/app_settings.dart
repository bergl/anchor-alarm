import '../domain/models.dart';

enum DistanceUnit { metres, feet }

enum ThemePref { system, day, night }

/// Base map choice. Seamarks (OpenSeaMap) is a separate overlay toggle.
/// [bathymetry]: EMODnet shaded depth + land relief (worldwide, best in Europe).
enum BaseMap { osm, satellite, bathymetry, none }

/// Depth overlay drawn over the base map.
enum DepthLayer {
  none,

  /// EMODnet Bathymetry (European waters, ~115 m grid).
  emodnet,

  /// GEBCO global bathymetric grid.
  gebco,
}

class AppSettings {
  const AppSettings({
    this.distanceUnit = DistanceUnit.metres,
    this.depthUnit = DistanceUnit.metres,
    this.theme = ThemePref.system,
    this.activeProfileId = AlarmProfile.overnightId,
    this.boat = const BoatSettings(),
    this.baseMap = BaseMap.osm,
    this.seamarks = true,
    this.depthLayer = DepthLayer.none,
    this.autoOfflineMap = true,
    this.keepScreenOn = false,
    this.useSimulator = false,
    this.onboardingDone = false,
    this.weatherAlerts = true,
    this.gustWarnKn = 25,
    this.windWarnKn = 20,
    this.waveWarnM = 1.5,
  });

  final DistanceUnit distanceUnit;
  final DistanceUnit depthUnit;
  final ThemePref theme;
  final String activeProfileId;
  final BoatSettings boat;
  final BaseMap baseMap;
  final bool seamarks;
  final DepthLayer depthLayer;

  /// Download the chart around the anchor when a watch starts (mobile only).
  final bool autoOfflineMap;
  final bool keepScreenOn;

  /// Use the GPS simulator instead of the device location (demo/testing).
  final bool useSimulator;
  final bool onboardingDone;

  /// Notify about forecast gusts, wind, wind shifts, waves and pressure
  /// drops while watching (informational, never the drag alarm).
  final bool weatherAlerts;

  /// Forecast alert thresholds: gusts and sustained wind in knots, waves in m.
  final double gustWarnKn;
  final double windWarnKn;
  final double waveWarnM;

  AppSettings copyWith({
    DistanceUnit? distanceUnit,
    DistanceUnit? depthUnit,
    ThemePref? theme,
    String? activeProfileId,
    BoatSettings? boat,
    BaseMap? baseMap,
    bool? seamarks,
    DepthLayer? depthLayer,
    bool? autoOfflineMap,
    bool? keepScreenOn,
    bool? useSimulator,
    bool? onboardingDone,
    bool? weatherAlerts,
    double? gustWarnKn,
    double? windWarnKn,
    double? waveWarnM,
  }) =>
      AppSettings(
        distanceUnit: distanceUnit ?? this.distanceUnit,
        depthUnit: depthUnit ?? this.depthUnit,
        theme: theme ?? this.theme,
        activeProfileId: activeProfileId ?? this.activeProfileId,
        boat: boat ?? this.boat,
        baseMap: baseMap ?? this.baseMap,
        seamarks: seamarks ?? this.seamarks,
        depthLayer: depthLayer ?? this.depthLayer,
        autoOfflineMap: autoOfflineMap ?? this.autoOfflineMap,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        useSimulator: useSimulator ?? this.useSimulator,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        weatherAlerts: weatherAlerts ?? this.weatherAlerts,
        gustWarnKn: gustWarnKn ?? this.gustWarnKn,
        windWarnKn: windWarnKn ?? this.windWarnKn,
        waveWarnM: waveWarnM ?? this.waveWarnM,
      );

  Map<String, Object?> toJson() => {
        'distanceUnit': distanceUnit.name,
        'depthUnit': depthUnit.name,
        'theme': theme.name,
        'activeProfileId': activeProfileId,
        'boat': boat.toJson(),
        'baseMap': baseMap.name,
        'seamarks': seamarks,
        'depthLayer': depthLayer.name,
        'autoOfflineMap': autoOfflineMap,
        'keepScreenOn': keepScreenOn,
        'useSimulator': useSimulator,
        'onboardingDone': onboardingDone,
        'weatherAlerts': weatherAlerts,
        'gustWarnKn': gustWarnKn,
        'windWarnKn': windWarnKn,
        'waveWarnM': waveWarnM,
      };

  factory AppSettings.fromJson(Map<String, Object?> j) {
    const d = AppSettings();
    T e<T extends Enum>(List<T> values, Object? v, T def) =>
        values.firstWhere((x) => x.name == v, orElse: () => def);
    return AppSettings(
      distanceUnit: e(DistanceUnit.values, j['distanceUnit'], d.distanceUnit),
      depthUnit: e(DistanceUnit.values, j['depthUnit'], d.depthUnit),
      theme: e(ThemePref.values, j['theme'], d.theme),
      activeProfileId: j['activeProfileId'] as String? ?? d.activeProfileId,
      boat: j['boat'] is Map
          ? BoatSettings.fromJson(Map<String, Object?>.from(j['boat'] as Map))
          : d.boat,
      baseMap: e(BaseMap.values, j['baseMap'], d.baseMap),
      seamarks: j['seamarks'] as bool? ?? d.seamarks,
      depthLayer: e(DepthLayer.values, j['depthLayer'], d.depthLayer),
      autoOfflineMap: j['autoOfflineMap'] as bool? ?? d.autoOfflineMap,
      keepScreenOn: j['keepScreenOn'] as bool? ?? d.keepScreenOn,
      useSimulator: j['useSimulator'] as bool? ?? d.useSimulator,
      onboardingDone: j['onboardingDone'] as bool? ?? d.onboardingDone,
      weatherAlerts: j['weatherAlerts'] as bool? ?? d.weatherAlerts,
      gustWarnKn: (j['gustWarnKn'] as num?)?.toDouble() ?? d.gustWarnKn,
      windWarnKn: (j['windWarnKn'] as num?)?.toDouble() ?? d.windWarnKn,
      waveWarnM: (j['waveWarnM'] as num?)?.toDouble() ?? d.waveWarnM,
    );
  }
}
