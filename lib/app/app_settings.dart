import '../domain/models.dart';

enum DistanceUnit { metres, feet }

enum ThemePref { system, day, night }

/// Base map choice. Seamarks (OpenSeaMap) is a separate overlay toggle.
enum BaseMap { osm, satellite, none }

class AppSettings {
  const AppSettings({
    this.distanceUnit = DistanceUnit.metres,
    this.depthUnit = DistanceUnit.metres,
    this.theme = ThemePref.system,
    this.activeProfileId = AlarmProfile.overnightId,
    this.boat = const BoatSettings(),
    this.baseMap = BaseMap.osm,
    this.seamarks = true,
    this.keepScreenOn = false,
    this.useSimulator = false,
    this.onboardingDone = false,
  });

  final DistanceUnit distanceUnit;
  final DistanceUnit depthUnit;
  final ThemePref theme;
  final String activeProfileId;
  final BoatSettings boat;
  final BaseMap baseMap;
  final bool seamarks;
  final bool keepScreenOn;

  /// Use the GPS simulator instead of the device location (demo/testing).
  final bool useSimulator;
  final bool onboardingDone;

  AppSettings copyWith({
    DistanceUnit? distanceUnit,
    DistanceUnit? depthUnit,
    ThemePref? theme,
    String? activeProfileId,
    BoatSettings? boat,
    BaseMap? baseMap,
    bool? seamarks,
    bool? keepScreenOn,
    bool? useSimulator,
    bool? onboardingDone,
  }) =>
      AppSettings(
        distanceUnit: distanceUnit ?? this.distanceUnit,
        depthUnit: depthUnit ?? this.depthUnit,
        theme: theme ?? this.theme,
        activeProfileId: activeProfileId ?? this.activeProfileId,
        boat: boat ?? this.boat,
        baseMap: baseMap ?? this.baseMap,
        seamarks: seamarks ?? this.seamarks,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        useSimulator: useSimulator ?? this.useSimulator,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );

  Map<String, Object?> toJson() => {
        'distanceUnit': distanceUnit.name,
        'depthUnit': depthUnit.name,
        'theme': theme.name,
        'activeProfileId': activeProfileId,
        'boat': boat.toJson(),
        'baseMap': baseMap.name,
        'seamarks': seamarks,
        'keepScreenOn': keepScreenOn,
        'useSimulator': useSimulator,
        'onboardingDone': onboardingDone,
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
      keepScreenOn: j['keepScreenOn'] as bool? ?? d.keepScreenOn,
      useSimulator: j['useSimulator'] as bool? ?? d.useSimulator,
      onboardingDone: j['onboardingDone'] as bool? ?? d.onboardingDone,
    );
  }
}
