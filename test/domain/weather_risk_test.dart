import 'dart:io';

import 'package:anchor_alarm/domain/weather.dart';
import 'package:anchor_alarm/domain/weather_risk.dart';
import 'package:anchor_alarm/services/weather/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

final t0 = DateTime.utc(2026, 10, 20, 12);
final now = t0.add(const Duration(minutes: 15));

/// UTC "HH:mm", so messages do not depend on the test machine's time zone.
String utc(DateTime t) =>
    '${t.toUtc().hour.toString().padLeft(2, '0')}:${t.toUtc().minute.toString().padLeft(2, '0')}';

/// Hourly forecast from t0 (+ [startOffset] hours). Missing values use the
/// calm defaults.
Forecast fc({
  List<double?>? wind,
  List<double?>? gust,
  List<double?>? dir,
  List<double?>? pressure,
  List<double?>? waves,
  int hours = 30,
  int startOffset = 0,
  WeatherConditions? current,
}) {
  double? at(List<double?>? l, int i, double? def) => l == null ? def : (i < l.length ? l[i] : def);
  return Forecast(
    fetchedAt: t0,
    location: const LatLng(43.16, 16.44),
    current: current,
    hourly: [
      for (var i = 0; i < hours; i++)
        WeatherConditions(
          time: t0.add(Duration(hours: i + startOffset)),
          windKn: at(wind, i, 8.0),
          gustKn: at(gust, i, 12.0),
          windDirDeg: at(dir, i, 180.0),
          pressureHpa: at(pressure, i, 1015.0),
          waveHeightM: at(waves, i, null),
        ),
    ],
  );
}

WeatherRisk analyze(Forecast f, {WeatherThresholds th = const WeatherThresholds()}) =>
    analyzeWeather(f, now, thresholds: th, formatTime: utc);

List<WeatherAlertKind> kinds(WeatherRisk r) => [for (final a in r.alerts) a.kind];

void main() {
  test('calm forecast: stats, no alerts', () {
    final r = analyze(fc());
    expect(r.alerts, isEmpty);
    expect(r.hasAlerts, isFalse);
    expect(r.maxGust!.value, 12);
    expect(r.maxGust!.time, t0, reason: 'first of equal peaks');
    expect(r.maxWind!.value, 8);
    expect(r.windShift, isNull);
    expect(r.maxWave, isNull);
    expect(r.pressureDrop, isNull);
    // Window: the current hour up to now + 24 h.
    expect(r.hours.first.time, t0);
    expect(r.hours.last.time, t0.add(const Duration(hours: 24)));
    expect(r.hours, hasLength(25));
  });

  test('hours before the current hour and after 24 h are ignored', () {
    final gust = List<double?>.filled(30, 12)..[0] = 40..[26] = 40;
    final f = fc(gust: gust, startOffset: -1);
    final r = analyze(f);
    expect(r.alerts, isEmpty, reason: '11:00 is past, 13:00 next day is beyond 24 h');
    expect(r.maxGust!.value, 12);
  });

  group('current', () {
    test('uses the current block when recent', () {
      final c = WeatherConditions(time: now, windKn: 11, gustKn: 15, windDirDeg: 315);
      final r = analyze(fc(current: c, waves: [0.6]));
      expect(r.current!.windKn, 11);
      expect(r.current!.waveHeightM, 0.6, reason: 'waves from the hour');
    });

    test('falls back to this hour when the current block is old', () {
      final c = WeatherConditions(
          time: now.subtract(const Duration(hours: 3)), windKn: 30);
      final r = analyze(fc(current: c));
      expect(r.current!.windKn, 8);
      expect(r.current!.time, t0);
    });

    test('none when the forecast has run out', () {
      final r = analyzeWeather(fc(hours: 3), now.add(const Duration(days: 2)));
      expect(r.current, isNull);
      expect(r.hours, isEmpty);
      expect(r.alerts, isEmpty);
    });
  });

  group('strong gusts', () {
    test('alert with onset, peak and direction', () {
      final gust = List<double?>.filled(30, 12);
      gust[13] = 26; // onset 01:00
      gust[15] = 32; // peak 03:00
      final dir = List<double?>.filled(30, 180)..[15] = 315;
      final r = analyze(fc(gust: gust, dir: dir));
      final a = r.alerts.single;
      expect(a.kind, WeatherAlertKind.strongGusts);
      expect(a.time, t0.add(const Duration(hours: 13)));
      expect(a.peakTime, t0.add(const Duration(hours: 15)));
      expect(a.value, 32);
      expect(a.fromDeg, 315);
      expect(a.message, 'Gusts to 32 kn expected around 03:00 from NW (over 25 kn from 01:00)');
      expect(r.maxGust!.time, t0.add(const Duration(hours: 15)));
    });

    test('peak = onset gives the short message', () {
      final gust = List<double?>.filled(30, 12)..[15] = 32;
      final dir = List<double?>.filled(30, 315.0);
      final r = analyze(fc(gust: gust, dir: dir));
      expect(r.alerts.single.message, 'Gusts to 32 kn expected around 03:00 from NW');
    });

    test('boundary: exactly the threshold alerts, just below does not', () {
      expect(kinds(analyze(fc(gust: List.filled(30, 25.0)))), [WeatherAlertKind.strongGusts]);
      expect(analyze(fc(gust: List.filled(30, 24.9))).alerts, isEmpty);
    });

    test('threshold from settings', () {
      final gust = List<double?>.filled(30, 18);
      expect(analyze(fc(gust: gust)).alerts, isEmpty);
      final r = analyze(fc(gust: gust), th: const WeatherThresholds(gustWarnKn: 18));
      expect(kinds(r), [WeatherAlertKind.strongGusts]);
    });
  });

  group('strong wind', () {
    test('alert', () {
      final wind = List<double?>.filled(30, 8)..[5] = 21..[6] = 23;
      final gust = List<double?>.filled(30, 12)..[5] = 24..[6] = 24; // below gust limit
      final r = analyze(fc(wind: wind, gust: gust));
      final a = r.alerts.single;
      expect(a.kind, WeatherAlertKind.strongWind);
      expect(a.time, t0.add(const Duration(hours: 5)));
      expect(a.value, 23);
      expect(a.message, 'Wind 23 kn expected around 18:00 from S (over 20 kn from 17:00)');
    });

    test('boundary', () {
      final g = List<double?>.filled(30, 12);
      expect(kinds(analyze(fc(wind: List.filled(30, 20.0), gust: g))),
          [WeatherAlertKind.strongWind]);
      expect(analyze(fc(wind: List.filled(30, 19.9), gust: g)).alerts, isEmpty);
    });
  });

  group('wind shift', () {
    test('veer of 90° within 6 h at 12 kn', () {
      final wind = List<double?>.filled(30, 12);
      final dir = List<double?>.filled(30, 315); // NW
      for (var i = 4; i < 30; i++) {
        dir[i] = 45; // NE from 16:00
      }
      final r = analyze(fc(wind: wind, dir: dir));
      final a = r.alerts.single;
      expect(a.kind, WeatherAlertKind.windShift);
      expect(a.time, t0.add(const Duration(hours: 4)));
      expect(a.value, 90);
      expect(a.fromDeg, 315);
      expect(a.toDeg, 45);
      expect(r.windShift!.veers, isTrue);
      expect(r.windShift!.start, t0);
      expect(a.message, startsWith('Wind veers NW → NE around 16:00, 12 kn'));
    });

    test('backing shift across north', () {
      final wind = List<double?>.filled(30, 15);
      final dir = List<double?>.filled(30, 20)..[3] = 300;
      final s = analyze(fc(wind: wind, dir: dir)).windShift!;
      expect(s.changeDeg, -80);
      expect(s.veers, isFalse);
    });

    test('boundary: 60° is not enough, 61° is', () {
      final wind = List<double?>.filled(30, 12);
      expect(analyze(fc(wind: wind, dir: List<double?>.filled(30, 100)..[2] = 160)).windShift,
          isNull);
      expect(analyze(fc(wind: wind, dir: List<double?>.filled(30, 100)..[2] = 161)).windShift,
          isNotNull);
    });

    test('light wind (< 10 kn) shifts are ignored, 10 kn counts', () {
      final dir = List<double?>.filled(30, 0)..[2] = 180;
      expect(analyze(fc(wind: List.filled(30, 9.9), dir: dir)).windShift, isNull);
      expect(analyze(fc(wind: List.filled(30, 10.0), dir: dir)).windShift, isNotNull);
      // Windy before, calm after: no shift.
      final wind = List<double?>.filled(30, 15)..[2] = 5;
      expect(analyze(fc(wind: wind, dir: dir)).windShift, isNull);
    });

    test('change spread over more than 6 h is not a shift; exactly 6 h is', () {
      final wind = List<double?>.filled(30, 12);
      // 15° per hour: 60° after 4 h... 105° after 7 h, but never > 60° within 6 h?
      // 6 h × 10°/h = 60° → none.
      final slow = [for (var i = 0; i < 30; i++) (i * 10.0) % 360];
      expect(analyze(fc(wind: wind, dir: slow)).windShift, isNull);
      final dir = List<double?>.filled(30, 0);
      for (var i = 6; i < 30; i++) {
        dir[i] = 90;
      }
      expect(analyze(fc(wind: wind, dir: dir)).windShift!.time,
          t0.add(const Duration(hours: 6)));
    });
  });

  group('waves', () {
    test('alert with onset and peak', () {
      final waves = List<double?>.filled(30, 0.5)..[8] = 1.6..[10] = 2.1;
      final a = analyze(fc(waves: waves)).alerts.single;
      expect(a.kind, WeatherAlertKind.highWaves);
      expect(a.time, t0.add(const Duration(hours: 8)));
      expect(a.value, 2.1);
      expect(a.message, 'Waves to 2.1 m expected around 22:00');
    });

    test('boundary and threshold', () {
      expect(kinds(analyze(fc(waves: List.filled(30, 1.5)))), [WeatherAlertKind.highWaves]);
      expect(analyze(fc(waves: List.filled(30, 1.49))).alerts, isEmpty);
      expect(analyze(fc(waves: List.filled(30, 1.2)),
              th: const WeatherThresholds(waveWarnM: 1)).alerts,
          hasLength(1));
    });

    test('no marine data → no wave stats', () {
      expect(analyze(fc()).maxWave, isNull);
    });
  });

  group('pressure drop', () {
    test('3.4 hPa in 3 h', () {
      final p = List<double?>.filled(30, 1015);
      p[5] = 1014;
      p[6] = 1013;
      p[7] = 1012;
      p[8] = 1010.6;
      for (var i = 9; i < 30; i++) {
        p[i] = 1010;
      }
      final r = analyze(fc(pressure: p));
      final a = r.alerts.single;
      expect(a.kind, WeatherAlertKind.pressureDrop);
      // 1015 (16:00) → 1012 (19:00) is the first window of 3 hPa; the
      // largest fall is 1014 (17:00) → 1010.6 (20:00) = 3.4.
      expect(a.time, t0.add(const Duration(hours: 4)));
      expect(a.value, closeTo(3.4, 1e-9));
      expect(r.pressureDrop!.start, t0.add(const Duration(hours: 5)));
      expect(a.message, 'Pressure falling 3.4 hPa in 3 h from 17:00 — possible squalls or a storm');
    });

    test('boundary: 3.0 counts, 2.9 does not', () {
      List<double?> fall(double d) {
        final p = List<double?>.filled(30, 1015);
        for (var i = 3; i < 30; i++) {
          p[i] = 1015 - d;
        }
        return p;
      }

      expect(kinds(analyze(fc(pressure: fall(3.0)))), [WeatherAlertKind.pressureDrop]);
      expect(analyze(fc(pressure: fall(2.9))).alerts, isEmpty);
    });

    test('rising pressure and missing values', () {
      final p = [for (var i = 0; i < 30; i++) 1000.0 + i];
      expect(analyze(fc(pressure: p)).pressureDrop, isNull);
      final gaps = List<double?>.filled(30, null);
      expect(analyze(fc(pressure: gaps)).pressureDrop, isNull);
    });

    test('a fall in the last 3 hours already counts', () {
      final p = List<double?>.filled(33, 1010)
        ..[0] = 1014
        ..[1] = 1013
        ..[2] = 1012;
      final f = fc(pressure: p, hours: 33, startOffset: -3);
      final a = analyze(f).alerts.single;
      expect(a.kind, WeatherAlertKind.pressureDrop);
      expect(a.time, t0.subtract(const Duration(hours: 3)));
    });
  });

  test('several alerts at once come in kind order', () {
    final f = fc(
      wind: List.filled(30, 22.0),
      gust: List.filled(30, 30.0),
      dir: List<double?>.filled(30, 0)..[3] = 90,
      waves: List.filled(30, 2.0),
      pressure: [for (var i = 0; i < 30; i++) 1020.0 - i * 1.5],
    );
    expect(kinds(analyze(f)), WeatherAlertKind.values);
  });

  test('null hours are skipped', () {
    final f = fc(wind: List.filled(30, null), gust: List.filled(30, null), dir: List.filled(30, null));
    final r = analyze(f);
    expect(r.maxGust, isNull);
    expect(r.maxWind, isNull);
    expect(r.alerts, isEmpty);
    expect(weatherSummary(r), isNull);
  });

  group('helpers', () {
    test('compass points', () {
      expect(compassPoint(0), 'N');
      expect(compassPoint(22.4), 'N');
      expect(compassPoint(22.5), 'NE');
      expect(compassPoint(315), 'NW');
      expect(compassPoint(359), 'N');
      expect(compassPoint(-45), 'NW');
      expect(compassPoint(360), 'N');
    });

    test('signed angle difference', () {
      expect(signedAngleDiff(350, 10), 20);
      expect(signedAngleDiff(10, 350), -20);
      expect(signedAngleDiff(0, 180), 180);
      expect(signedAngleDiff(90, 90), 0);
    });

    test('summary line for the HUD', () {
      final gust = List<double?>.filled(30, 18)..[15] = 28;
      final r = analyze(fc(
        gust: gust,
        dir: List.filled(30, 315.0),
        current: WeatherConditions(time: now, windKn: 12.4, gustKn: 18, windDirDeg: 315),
      ));
      expect(weatherSummary(r, formatTime: utc), 'Wind 12 kn NW · gusts 18 · max 28 kn 03:00');
      // Max equal to the current gust: no "max" part.
      final calm = analyze(fc(
          current: WeatherConditions(time: now, windKn: 8, gustKn: 12, windDirDeg: 180)));
      expect(weatherSummary(calm, formatTime: utc), 'Wind 8 kn S · gusts 12');
    });

    test('anchoring outlook (12 h)', () {
      final wind = List<double?>.filled(30, 12);
      final dir = List<double?>.filled(30, 315);
      for (var i = 5; i < 30; i++) {
        dir[i] = 45;
      }
      final gust = List<double?>.filled(30, 15)..[8] = 24..[20] = 40; // 20 h is beyond 12 h
      final text = anchoringOutlook(fc(wind: wind, dir: dir, gust: gust), now);
      expect(text, 'Next 12 h: wind veers NW→NE, gusts to 24 kn');
      final calm = anchoringOutlook(fc(waves: List.filled(30, 0.8)), now);
      expect(calm, 'Next 12 h: wind S up to 8 kn, gusts to 12 kn, waves to 0.8 m');
      expect(anchoringOutlook(fc(hours: 2), now.add(const Duration(days: 1))), isNull);
    });
  });

  test('hand-made Open-Meteo fixture (Hvar, bora night)', () {
    final f = WeatherService.parseForecast(
      File('test/fixtures/open_meteo/forecast_hvar.json').readAsStringSync(),
      location: const LatLng(43.16, 16.44),
      fetchedAt: now,
    )!;
    final waves = WeatherService.parseMarine(
        File('test/fixtures/open_meteo/marine_hvar.json').readAsStringSync())!;
    final r = analyzeWeather(WeatherService.mergeMarine(f, waves), now, formatTime: utc);
    expect(r.current!.windKn, 11.8);
    expect(r.maxGust!.value, 32.4);
    expect(r.maxGust!.time, DateTime.utc(2026, 10, 21, 1));
    expect(kinds(r), WeatherAlertKind.values);
    final byKind = {for (final a in r.alerts) a.kind: a};
    expect(byKind[WeatherAlertKind.strongGusts]!.message,
        'Gusts to 32 kn expected around 01:00 from NE (over 25 kn from 00:00)');
    expect(byKind[WeatherAlertKind.windShift]!.message,
        startsWith('Wind backs SE → NE around 00:00, 21 kn'));
    expect(byKind[WeatherAlertKind.pressureDrop]!.time, DateTime.utc(2026, 10, 20, 18));
    expect(byKind[WeatherAlertKind.pressureDrop]!.value, closeTo(4.2, 1e-9));
    expect(byKind[WeatherAlertKind.highWaves]!.value, 1.8);
  });
}
