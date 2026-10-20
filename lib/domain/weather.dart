import 'package:latlong2/latlong.dart';

/// Conditions at one moment. Wind in knots, direction in degrees the wind
/// comes FROM (meteorological convention), pressure in hPa (mean sea level),
/// precipitation in mm (over the preceding hour), waves in metres / seconds.
/// Any value can be missing (null) when the model has no data.
class WeatherConditions {
  const WeatherConditions({
    required this.time,
    this.windKn,
    this.gustKn,
    this.windDirDeg,
    this.pressureHpa,
    this.precipitationMm,
    this.weatherCode,
    this.waveHeightM,
    this.waveDirDeg,
    this.wavePeriodS,
  });

  /// UTC.
  final DateTime time;
  final double? windKn;
  final double? gustKn;
  final double? windDirDeg;
  final double? pressureHpa;
  final double? precipitationMm;

  /// WMO weather interpretation code.
  final int? weatherCode;
  final double? waveHeightM;
  final double? waveDirDeg;
  final double? wavePeriodS;

  WeatherConditions withWaves({double? heightM, double? dirDeg, double? periodS}) =>
      WeatherConditions(
        time: time,
        windKn: windKn,
        gustKn: gustKn,
        windDirDeg: windDirDeg,
        pressureHpa: pressureHpa,
        precipitationMm: precipitationMm,
        weatherCode: weatherCode,
        waveHeightM: heightM,
        waveDirDeg: dirDeg,
        wavePeriodS: periodS,
      );

  Map<String, Object?> toJson() => {
        't': time.millisecondsSinceEpoch,
        if (windKn != null) 'w': windKn,
        if (gustKn != null) 'g': gustKn,
        if (windDirDeg != null) 'wd': windDirDeg,
        if (pressureHpa != null) 'p': pressureHpa,
        if (precipitationMm != null) 'r': precipitationMm,
        if (weatherCode != null) 'c': weatherCode,
        if (waveHeightM != null) 'h': waveHeightM,
        if (waveDirDeg != null) 'hd': waveDirDeg,
        if (wavePeriodS != null) 'hp': wavePeriodS,
      };

  factory WeatherConditions.fromJson(Map<String, Object?> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return WeatherConditions(
      time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int, isUtc: true),
      windKn: d('w'),
      gustKn: d('g'),
      windDirDeg: d('wd'),
      pressureHpa: d('p'),
      precipitationMm: d('r'),
      weatherCode: (j['c'] as num?)?.toInt(),
      waveHeightM: d('h'),
      waveDirDeg: d('hd'),
      wavePeriodS: d('hp'),
    );
  }
}

/// One hour of the forecast ([time] is the start of the hour, UTC).
typedef HourlyWeather = WeatherConditions;

/// A weather forecast for one position, as fetched (and cached).
class Forecast {
  const Forecast({
    required this.fetchedAt,
    required this.location,
    required this.hourly,
    this.current,
    this.utcOffsetSeconds = 0,
    this.timezone,
    this.hasMarine = false,
  });

  /// When the app received it (UTC).
  final DateTime fetchedAt;

  /// Position the forecast was requested for.
  final LatLng location;

  /// "Current" conditions (Open-Meteo: 15-minutely model values).
  final WeatherConditions? current;

  /// Hourly steps, oldest first, UTC.
  final List<HourlyWeather> hourly;

  /// Offset of the forecast location's time zone (informational).
  final int utcOffsetSeconds;
  final String? timezone;

  /// Wave data was available (sea area covered by the marine model).
  final bool hasMarine;

  Duration age(DateTime now) => now.difference(fetchedAt);

  Map<String, Object?> toJson() => {
        'v': 1,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'lat': location.latitude,
        'lon': location.longitude,
        if (current != null) 'current': current!.toJson(),
        'hourly': [for (final h in hourly) h.toJson()],
        'utcOffset': utcOffsetSeconds,
        if (timezone != null) 'tz': timezone,
        'marine': hasMarine,
      };

  factory Forecast.fromJson(Map<String, Object?> j) => Forecast(
        fetchedAt:
            DateTime.fromMillisecondsSinceEpoch(j['fetchedAt'] as int, isUtc: true),
        location: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        current: j['current'] is Map
            ? WeatherConditions.fromJson(Map<String, Object?>.from(j['current'] as Map))
            : null,
        hourly: [
          for (final h in (j['hourly'] as List? ?? const []))
            WeatherConditions.fromJson(Map<String, Object?>.from(h as Map)),
        ],
        utcOffsetSeconds: (j['utcOffset'] as num?)?.toInt() ?? 0,
        timezone: j['tz'] as String?,
        hasMarine: j['marine'] as bool? ?? false,
      );
}
