import 'dart:io';

import 'package:anchor_alarm/services/weather/weather_service.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

// Fixtures in test/fixtures/open_meteo/ are HAND-MADE (open-meteo.com was not
// reachable from the build environment). They follow the documented
// Open-Meteo response format: latitude, longitude, utc_offset_seconds,
// timezone, current_units/current, hourly_units/hourly{time:[...], ...}.
String fixture(String name) => File('test/fixtures/open_meteo/$name').readAsStringSync();

const hvar = LatLng(43.16, 16.44);
final fetchedAt = DateTime.utc(2026, 10, 20, 12, 15);

http.Client client({
  String? forecast,
  int forecastStatus = 200,
  String? marine,
  int marineStatus = 200,
  List<Uri>? log,
}) =>
    MockClient((req) async {
      log?.add(req.url);
      if (req.url.host == 'api.open-meteo.com') {
        return http.Response(forecast ?? fixture('forecast_hvar.json'), forecastStatus,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (req.url.host == 'marine-api.open-meteo.com') {
        if (marine == null) throw const SocketException('no route');
        return http.Response(marine, marineStatus,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });

Future<WeatherResult> fetch(http.Client c, {Duration? timeout}) => withClock(
      Clock.fixed(fetchedAt),
      () => WeatherService(client: c, timeout: timeout ?? const Duration(seconds: 10))
          .fetch(hvar),
    );

void main() {
  group('request', () {
    test('forecast URL has the documented parameters', () {
      final u = WeatherService.forecastUrl(hvar);
      expect(u.scheme, 'https');
      expect(u.host, 'api.open-meteo.com');
      expect(u.path, '/v1/forecast');
      expect(u.queryParameters, {
        'latitude': '43.1600',
        'longitude': '16.4400',
        'hourly': 'wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,'
            'precipitation,weather_code',
        'current': 'wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl',
        'wind_speed_unit': 'kn',
        'timezone': 'auto',
        'timeformat': 'unixtime',
        'forecast_days': '3',
        'past_hours': '3',
      });
    });

    test('marine URL', () {
      final u = WeatherService.marineUrl(hvar);
      expect(u.host, 'marine-api.open-meteo.com');
      expect(u.path, '/v1/marine');
      expect(u.queryParameters['hourly'], 'wave_height,wave_direction,wave_period');
      expect(u.queryParameters['timeformat'], 'unixtime');
      expect(u.queryParameters['timezone'], 'auto');
    });
  });

  group('time conversion', () {
    test('local ISO time minus utc_offset_seconds = UTC', () {
      expect(WeatherService.parseTime('2026-10-20T14:00', 7200), DateTime.utc(2026, 10, 20, 12));
      expect(WeatherService.parseTime('2026-10-21T00:00', -14400), DateTime.utc(2026, 10, 21, 4));
      expect(WeatherService.parseTime('2026-10-21T01:30', 19800), DateTime.utc(2026, 10, 20, 20));
      expect(WeatherService.parseTime('2026-10-20T14:00', 0), DateTime.utc(2026, 10, 20, 14));
      expect(WeatherService.parseTime('2026-10-20T14:00', 0)!.isUtc, isTrue);
    });

    test('unix seconds and garbage', () {
      expect(WeatherService.parseTime(1792497600, 7200),
          DateTime.fromMillisecondsSinceEpoch(1792497600000, isUtc: true));
      expect(WeatherService.parseTime('yesterday', 0), isNull);
      expect(WeatherService.parseTime(null, 0), isNull);
    });
  });

  group('fetch', () {
    test('parses forecast + marine (UTC+2 local times)', () async {
      final log = <Uri>[];
      final r = await fetch(client(marine: fixture('marine_hvar.json'), log: log));
      expect(log.map((u) => u.host).toSet(),
          {'api.open-meteo.com', 'marine-api.open-meteo.com'});
      final f = (r as WeatherOk).forecast;
      expect(f.fetchedAt, fetchedAt);
      expect(f.location, hvar);
      expect(f.utcOffsetSeconds, 7200);
      expect(f.timezone, 'Europe/Zagreb');
      expect(f.hasMarine, isTrue);

      // First hour 11:00 local = 09:00 UTC; last 2026-10-22T23:00 local.
      expect(f.hourly.first.time, DateTime.utc(2026, 10, 20, 9));
      expect(f.hourly.last.time, DateTime.utc(2026, 10, 22, 21));
      expect(f.hourly, hasLength(61));
      expect(f.hourly.every((h) => h.time.isUtc), isTrue);

      // 03:00 local on the 21st = 01:00 UTC: the bora peak.
      final peak = f.hourly.firstWhere((h) => h.time == DateTime.utc(2026, 10, 21, 1));
      expect(peak.windKn, 22.0);
      expect(peak.gustKn, 32.4);
      expect(peak.windDirDeg, 45);
      expect(peak.pressureHpa, 1010.0);
      expect(peak.waveHeightM, 0.75);
      expect(peak.waveDirDeg, 50);
      expect(peak.wavePeriodS, 4.2);
      expect(peak.weatherCode, 3);
      expect(peak.precipitationMm, 0.0);
      final rainy = f.hourly.firstWhere((h) => h.time == DateTime.utc(2026, 10, 20, 23));
      expect(rainy.weatherCode, 61);
      expect(rainy.precipitationMm, 0.4);

      final c = f.current!;
      expect(c.time, DateTime.utc(2026, 10, 20, 12, 15));
      expect(c.windKn, 11.8);
      expect(c.gustKn, 16.3);
      expect(c.windDirDeg, 138);
      expect(c.pressureHpa, 1014.3);
    });

    test('negative offset (New York) and null values', () async {
      final r = await fetch(client(forecast: fixture('forecast_new_york.json')));
      final f = (r as WeatherOk).forecast;
      expect(f.utcOffsetSeconds, -14400);
      expect([for (final h in f.hourly) h.time], [
        DateTime.utc(2026, 10, 21, 2),
        DateTime.utc(2026, 10, 21, 3),
        DateTime.utc(2026, 10, 21, 4),
        DateTime.utc(2026, 10, 21, 5),
      ]);
      expect(f.current!.time, DateTime.utc(2026, 10, 21, 3, 45));
      final last = f.hourly.last;
      expect(last.windKn, isNull);
      expect(last.gustKn, isNull);
      expect(last.pressureHpa, isNull);
      expect(last.weatherCode, isNull);
      expect(f.hasMarine, isFalse);
    });

    test('inland: marine with only nulls → no waves', () async {
      final r = await fetch(client(marine: fixture('marine_inland.json')));
      final f = (r as WeatherOk).forecast;
      expect(f.hasMarine, isFalse);
      expect(f.hourly.every((h) => h.waveHeightM == null), isTrue);
    });

    test('marine error or unreachable → forecast without waves', () async {
      var r = await fetch(client(marine: fixture('error_400.json'), marineStatus: 400));
      expect((r as WeatherOk).forecast.hasMarine, isFalse);
      r = await fetch(client(marine: null)); // throws SocketException
      expect((r as WeatherOk).forecast.hourly, hasLength(61));
    });

    test('forecast API error → WeatherError with the reason', () async {
      final r = await fetch(client(forecast: fixture('error_400.json'), forecastStatus: 400));
      expect((r as WeatherError).message, contains('Latitude must be in range'));
    });

    test('HTTP 5xx with HTML body', () async {
      final r = await fetch(client(forecast: '<html>502 Bad Gateway</html>', forecastStatus: 502));
      expect((r as WeatherError).message, 'Weather server error 502');
    });

    test('offline', () async {
      final r = await fetch(MockClient((_) async => throw const SocketException('offline')));
      expect((r as WeatherError).message, 'No connection to the weather service');
    });

    test('timeout', () async {
      final slow = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response(fixture('forecast_hvar.json'), 200);
      });
      final sw = Stopwatch()..start();
      final r = await fetch(slow, timeout: const Duration(milliseconds: 50));
      expect((r as WeatherError).message, 'Weather request timed out');
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('200 with an unusable body', () async {
      for (final body in ['{}', '[]', 'nonsense', '{"hourly":{"time":[]}}']) {
        final r = await fetch(client(forecast: body));
        expect(r, isA<WeatherError>(), reason: body);
      }
    });
  });
}
