import 'package:anchor_alarm/domain/anchorage_assessment.dart';
import 'package:anchor_alarm/domain/exposure.dart';
import 'package:anchor_alarm/domain/weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const anchor = LatLng(43.1673, 16.3942);
const t = ExposureThresholds();

/// Sheltered except S–W (indices 8–12) with 3.8 km fetch and NW (14)
/// partly open with 1.2 km.
ExposureProfile bayOpenSouthWest() => ExposureProfile(
      anchor: anchor,
      thresholds: t,
      source: 'test',
      sectors: [
        for (var i = 0; i < 16; i++)
          SectorExposure(
            index: i,
            fetchM: i >= 8 && i <= 12 ? 3800 : (i == 14 ? 1200 : 300),
            rating: t.rate(i >= 8 && i <= 12 ? 3800 : (i == 14 ? 1200 : 300)),
            capped: false,
          ),
      ],
    );

final now = DateTime.utc(2026, 10, 20, 18, 10);

String utcHm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 30 hourly steps from 18:00 UTC; [wind] gives (kn, gust, from) per hour.
Forecast forecast((double, double?, double) Function(int i) wind) => Forecast(
      fetchedAt: now,
      location: anchor,
      hourly: [
        for (var i = 0; i < 30; i++)
          () {
            final (kn, gust, dir) = wind(i);
            return WeatherConditions(
              time: DateTime.utc(2026, 10, 20, 18).add(Duration(hours: i)),
              windKn: kn,
              gustKn: gust,
              windDirDeg: dir,
            );
          }(),
      ],
    );

void main() {
  test('strong SW wind into an anchorage open to the SW: poor', () {
    // 18:00 → +8 h = 02:00 … 05:00: SW 18 kn; NE 10 kn otherwise.
    final f = forecast((i) => i >= 8 && i <= 11 ? (18, 22, 225) : (10, 14, 45));
    final a = assessAnchorage(
        exposure: bayOpenSouthWest(), forecast: f, now: now, formatTime: utcHm);
    expect(a.rating, AnchorageRating.poor);
    expect(a.windows, hasLength(1));
    final w = a.windows.single;
    expect(w.start, DateTime.utc(2026, 10, 21, 2));
    expect(w.end, DateTime.utc(2026, 10, 21, 6));
    expect(w.severe, isTrue);
    expect(a.advice, contains(
        'Exposed to SW (fetch 3.8 km): SW 18 kn expected 02:00–06:00 — consider another anchorage.'));
    expect(a.advice.first, startsWith('Sheltered from'));
    expect(a.summary, 'Exposed to SW 18 kn at 02:00');
    // The current hour plus the next 24.
    expect(a.hours, hasLength(25));
    expect(a.hours.where((h) => h.risk == HourRisk.exposed), hasLength(4));
  });

  test('gusts make the summary mention them', () {
    final f = forecast((i) => i == 9 ? (16, 26, 225) : (8, 10, 45));
    final a = assessAnchorage(
        exposure: bayOpenSouthWest(), forecast: f, now: now, formatTime: utcHm);
    expect(a.rating, AnchorageRating.poor);
    expect(a.summary, 'Exposed to SW gusts 26 kn at 03:00');
    expect(a.advice.last, contains('SW 16 kn, gusts 26 kn expected 03:00–04:00'));
  });

  test('NE wind on the sheltered side: good', () {
    final f = forecast((i) => (15, 20, 45));
    final a = assessAnchorage(
        exposure: bayOpenSouthWest(), forecast: f, now: now, formatTime: utcHm);
    expect(a.rating, AnchorageRating.good);
    expect(a.windows, isEmpty);
    expect(a.summary, 'Good shelter for the forecast NE 15 kn');
    expect(a.advice.last, 'No wind of 12 kn or more from an exposed direction in the next 24 h.');
  });

  test('moderate wind from an exposed side: caution, chop', () {
    final f = forecast((i) => i < 3 ? (13, 16, 200) : (5, 7, 45));
    final a = assessAnchorage(
        exposure: bayOpenSouthWest(), forecast: f, now: now, formatTime: utcHm);
    expect(a.rating, AnchorageRating.caution);
    expect(a.windows.single.severe, isFalse);
    expect(a.advice.last, endsWith('— expect chop.'));
    expect(a.summary, 'Exposed to SSW 13 kn at 18:00');
  });

  test('wind under 12 kn from an exposed side does not count', () {
    final f = forecast((i) => (11, 14, 225));
    final a = assessAnchorage(
        exposure: bayOpenSouthWest(), forecast: f, now: now, formatTime: utcHm);
    expect(a.rating, AnchorageRating.good);
    expect(a.summary, 'Light winds (max 11 kn) — good for the next 24 h');
  });

  test('strong wind from a partly open side: caution', () {
    final f = forecast((i) => i >= 2 && i <= 4 ? (22, 28, 315) : (6, 8, 45));
    final a = assessAnchorage(
        exposure: bayOpenSouthWest(), forecast: f, now: now, formatTime: utcHm);
    expect(a.rating, AnchorageRating.caution);
    expect(a.windows.single.risk, HourRisk.partly);
    expect(a.advice.last,
        'Partly open to NW (fetch 1.2 km): NW 22 kn, gusts 28 kn expected 20:00–23:00 — expect some chop.');
    expect(a.summary, 'Some chop: NW 22 kn at 20:00');
  });

  test('without forecast: shelter only', () {
    final a = assessAnchorage(exposure: bayOpenSouthWest(), forecast: null, now: now);
    expect(a.rating, isNull);
    expect(a.hasForecast, isFalse);
    expect(a.summary, 'Open to S–W (no forecast)');
    expect(a.advice.single, startsWith('Sheltered from'));
  });

  test('without land data: forecast only', () {
    final f = forecast((i) => i == 5 ? (18, 30, 225) : (8, 12, 225));
    final a = assessAnchorage(exposure: null, forecast: f, now: now);
    expect(a.rating, AnchorageRating.caution);
    expect(a.summary, 'No shelter data · SW up to 18 kn, gusts 30 kn');
    expect(a.advice.single, startsWith('Shelter could not be analysed'));
    expect(a.hours.every((h) => h.rating == null && h.risk == HourRisk.none), isTrue);

    final calm = assessAnchorage(
        exposure: null, forecast: forecast((i) => (8, 12, 225)), now: now);
    expect(calm.rating, isNull);
  });

  test('nothing at all', () {
    final a = assessAnchorage(exposure: null, forecast: null, now: now);
    expect(a.rating, isNull);
    expect(a.summary, 'No shelter or forecast data');
  });

  test('past forecast hours are ignored', () {
    final f = forecast((i) => (25, 30, 225));
    final a = assessAnchorage(
        exposure: bayOpenSouthWest(),
        forecast: f,
        now: DateTime.utc(2026, 10, 23),
        formatTime: utcHm);
    expect(a.hasForecast, isFalse);
    expect(a.rating, isNull);
  });
}
