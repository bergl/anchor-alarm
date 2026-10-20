import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/domain/weather.dart';
import 'package:anchor_alarm/services/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Forecast sample() => Forecast(
      fetchedAt: DateTime.utc(2026, 10, 20, 12, 5),
      location: const LatLng(43.16, 16.44),
      current: WeatherConditions(
          time: DateTime.utc(2026, 10, 20, 12), windKn: 11.8, gustKn: 16.3, windDirDeg: 138),
      hourly: [
        WeatherConditions(
          time: DateTime.utc(2026, 10, 20, 12),
          windKn: 9,
          gustKn: 12.2,
          windDirDeg: 135,
          pressureHpa: 1014.2,
          precipitationMm: 0,
          weatherCode: 3,
          waveHeightM: 0.4,
          waveDirDeg: 140,
          wavePeriodS: 3.1,
        ),
        WeatherConditions(time: DateTime.utc(2026, 10, 20, 13)),
      ],
      utcOffsetSeconds: 7200,
      timezone: 'Europe/Zagreb',
      hasMarine: true,
    );

void expectSame(Forecast a, Forecast b) {
  expect(b.toJson(), a.toJson());
  expect(b.fetchedAt, a.fetchedAt);
  expect(b.fetchedAt.isUtc, isTrue);
  expect(b.hourly.first.time.isUtc, isTrue);
  expect(b.hourly.first.wavePeriodS, 3.1);
  expect(b.hourly.last.windKn, isNull);
  expect(b.current!.gustKn, 16.3);
}

void main() {
  test('Forecast JSON round trip', () {
    final f = sample();
    expectSame(f, Forecast.fromJson(f.toJson()));
  });

  test('sembast weather cache round trip', () async {
    final db = await openAppDatabase(inMemory: true);
    addTearDown(db.close);
    expect(await db.weather.load(), isNull);
    await db.weather.save(sample());
    expectSame(sample(), (await db.weather.load())!);
  });

  test('AppSettings weather fields: defaults, round trip, old JSON', () {
    const d = AppSettings();
    expect(d.weatherAlerts, isTrue);
    expect(d.gustWarnKn, 25);
    expect(d.windWarnKn, 20);
    expect(d.waveWarnM, 1.5);

    final s = d.copyWith(weatherAlerts: false, gustWarnKn: 30, windWarnKn: 22, waveWarnM: 2);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.weatherAlerts, isFalse);
    expect(back.gustWarnKn, 30);
    expect(back.windWarnKn, 22);
    expect(back.waveWarnM, 2);

    // Settings saved before weather existed.
    final old = AppSettings.fromJson({'distanceUnit': 'feet', 'onboardingDone': true});
    expect(old.weatherAlerts, isTrue);
    expect(old.gustWarnKn, 25);
    expect(old.waveWarnM, 1.5);
    // Integers in JSON.
    expect(AppSettings.fromJson({'gustWarnKn': 28}).gustWarnKn, 28.0);
  });
}
