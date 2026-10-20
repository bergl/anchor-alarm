import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/weather.dart';

/// Result of [WeatherService.fetch]: a forecast or a short error message.
sealed class WeatherResult {
  const WeatherResult();
}

class WeatherOk extends WeatherResult {
  const WeatherOk(this.forecast);
  final Forecast forecast;
}

class WeatherError extends WeatherResult {
  const WeatherError(this.message);
  final String message;
}

/// Wind, pressure and waves from Open-Meteo (free, no API key, CORS enabled).
///
/// * Forecast API `api.open-meteo.com/v1/forecast`: hourly wind, gusts,
///   direction, MSL pressure, precipitation and weather code, plus "current"
///   values; knots, Unix times (`timeformat=unixtime`), 3 days ahead and the last 3 hours.
/// * Marine API `marine-api.open-meteo.com/v1/marine`: hourly wave height,
///   direction and period. Optional: inland, outside the model or on error
///   the forecast simply has no waves.
///
/// Open-Meteo returns local times (`2026-10-20T14:00`, no offset) for the
/// requested time zone plus `utc_offset_seconds`; they are converted to UTC.
/// Never throws: failures (offline, HTTP/API error, bad body, [timeout])
/// return a [WeatherError].
class WeatherService {
  WeatherService({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const attribution = 'Weather data by Open-Meteo.com (CC BY 4.0)';

  static String _coord(double v) => v.toStringAsFixed(4);

  static Uri forecastUrl(LatLng p) => Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': _coord(p.latitude),
        'longitude': _coord(p.longitude),
        'hourly': 'wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,'
            'precipitation,weather_code',
        'current': 'wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl',
        'wind_speed_unit': 'kn',
        'timezone': 'auto',
        // Unix times avoid a one-hour error across a daylight-saving change
        // (one utc_offset_seconds applies to the whole response).
        'timeformat': 'unixtime',
        'forecast_days': '3',
        'past_hours': '3',
      });

  static Uri marineUrl(LatLng p) =>
      Uri.https('marine-api.open-meteo.com', '/v1/marine', {
        'latitude': _coord(p.latitude),
        'longitude': _coord(p.longitude),
        'hourly': 'wave_height,wave_direction,wave_period',
        'timezone': 'auto',
        // Unix times avoid a one-hour error across a daylight-saving change
        // (one utc_offset_seconds applies to the whole response).
        'timeformat': 'unixtime',
        'forecast_days': '3',
        'past_hours': '3',
      });

  Future<WeatherResult> fetch(LatLng p) async {
    final now = clock.now().toUtc();
    // Both in parallel; marine never fails the whole fetch.
    final marineFuture = _marine(p);
    final String body;
    try {
      final res = await _client.get(forecastUrl(p)).timeout(timeout);
      if (res.statusCode != 200) {
        return WeatherError(_apiReason(res.body) ?? 'Weather server error ${res.statusCode}');
      }
      body = res.body;
    } on TimeoutException {
      return const WeatherError('Weather request timed out');
    } catch (_) {
      return const WeatherError('No connection to the weather service');
    }
    final forecast = parseForecast(body, location: p, fetchedAt: now);
    if (forecast == null) return const WeatherError('Unreadable weather data');
    final waves = await marineFuture;
    return WeatherOk(waves == null ? forecast : mergeMarine(forecast, waves));
  }

  Future<Map<DateTime, ({double? h, double? d, double? p})>?> _marine(LatLng p) async {
    try {
      final res = await _client.get(marineUrl(p)).timeout(timeout);
      if (res.statusCode != 200) return null;
      return parseMarine(res.body);
    } catch (_) {
      return null;
    }
  }

  /// `reason` of an Open-Meteo error body (`{"error":true,"reason":"..."}`).
  static String? _apiReason(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] == true && j['reason'] is String) {
        return 'Weather service: ${j['reason']}';
      }
    } catch (_) {}
    return null;
  }

  /// Converts an Open-Meteo time to UTC: ISO local time without offset
  /// (`2026-10-20T14:00`) shifted by [utcOffsetSeconds], or unix seconds.
  static DateTime? parseTime(Object? v, int utcOffsetSeconds) {
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000, isUtc: true);
    }
    if (v is! String) return null;
    // Parse the wall-clock time as if it were UTC, then remove the offset.
    final wall = DateTime.tryParse(v.endsWith('Z') ? v : '${v}Z');
    if (wall == null) return null;
    return wall.subtract(Duration(seconds: utcOffsetSeconds));
  }

  static double? _num(List? l, int i) {
    if (l == null || i >= l.length) return null;
    final v = l[i];
    return v is num ? v.toDouble() : null;
  }

  /// Parses a forecast API body; null when it is not a usable forecast.
  static Forecast? parseForecast(String body,
      {required LatLng location, required DateTime fetchedAt}) {
    try {
      final j = jsonDecode(body);
      if (j is! Map || j['error'] == true) return null;
      final offset = (j['utc_offset_seconds'] as num?)?.toInt() ?? 0;
      final hourly = j['hourly'];
      if (hourly is! Map || hourly['time'] is! List) return null;
      final times = hourly['time'] as List;
      List? col(String k) => hourly[k] is List ? hourly[k] as List : null;
      final ws = col('wind_speed_10m'),
          wg = col('wind_gusts_10m'),
          wd = col('wind_direction_10m'),
          pr = col('pressure_msl'),
          pc = col('precipitation'),
          wc = col('weather_code');
      final hours = <WeatherConditions>[];
      for (var i = 0; i < times.length; i++) {
        final t = parseTime(times[i], offset);
        if (t == null) continue;
        hours.add(WeatherConditions(
          time: t,
          windKn: _num(ws, i),
          gustKn: _num(wg, i),
          windDirDeg: _num(wd, i),
          pressureHpa: _num(pr, i),
          precipitationMm: _num(pc, i),
          weatherCode: _num(wc, i)?.toInt(),
        ));
      }
      if (hours.isEmpty) return null;
      hours.sort((a, b) => a.time.compareTo(b.time));

      WeatherConditions? current;
      final c = j['current'];
      if (c is Map) {
        final t = parseTime(c['time'], offset);
        double? n(String k) => c[k] is num ? (c[k] as num).toDouble() : null;
        if (t != null) {
          current = WeatherConditions(
            time: t,
            windKn: n('wind_speed_10m'),
            gustKn: n('wind_gusts_10m'),
            windDirDeg: n('wind_direction_10m'),
            pressureHpa: n('pressure_msl'),
          );
        }
      }
      return Forecast(
        fetchedAt: fetchedAt.toUtc(),
        location: location,
        current: current,
        hourly: hours,
        utcOffsetSeconds: offset,
        timezone: j['timezone'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses a marine API body into waves by UTC hour; null when there is no
  /// wave data at all (error body, inland point with only nulls).
  static Map<DateTime, ({double? h, double? d, double? p})>? parseMarine(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map || j['error'] == true) return null;
      final offset = (j['utc_offset_seconds'] as num?)?.toInt() ?? 0;
      final hourly = j['hourly'];
      if (hourly is! Map || hourly['time'] is! List) return null;
      final times = hourly['time'] as List;
      List? col(String k) => hourly[k] is List ? hourly[k] as List : null;
      final wh = col('wave_height'), wd = col('wave_direction'), wp = col('wave_period');
      final out = <DateTime, ({double? h, double? d, double? p})>{};
      for (var i = 0; i < times.length; i++) {
        final t = parseTime(times[i], offset);
        final h = _num(wh, i);
        if (t == null || h == null) continue;
        out[t] = (h: h, d: _num(wd, i), p: _num(wp, i));
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// Adds waves to the matching forecast hours.
  static Forecast mergeMarine(
      Forecast f, Map<DateTime, ({double? h, double? d, double? p})> waves) {
    var any = false;
    final hours = <WeatherConditions>[];
    for (final h in f.hourly) {
      final w = waves[h.time];
      if (w == null) {
        hours.add(h);
      } else {
        any = true;
        hours.add(h.withWaves(heightM: w.h, dirDeg: w.d, periodS: w.p));
      }
    }
    return Forecast(
      fetchedAt: f.fetchedAt,
      location: f.location,
      current: f.current,
      hourly: hours,
      utcOffsetSeconds: f.utcOffsetSeconds,
      timezone: f.timezone,
      hasMarine: any,
    );
  }

  void close() => _client.close();
}
