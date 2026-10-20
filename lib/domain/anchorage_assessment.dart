import 'dart:math' as math;

import 'exposure.dart';
import 'weather.dart';
import 'weather_risk.dart' show TimeFormatter, defaultTimeFormat;

/// Overall verdict of the anchorage check.
enum AnchorageRating { good, caution, poor }

/// How one forecast hour affects the anchorage.
enum HourRisk {
  /// Light wind, or wind from a sheltered direction.
  none,

  /// Strong wind from a partly open direction: chop.
  partly,

  /// Wind from an exposed direction (long fetch).
  exposed,
}

/// Wind limits of the check (inclusive).
class AssessmentThresholds {
  const AssessmentThresholds({
    this.minWindKn = 12,
    this.poorWindKn = 15,
    this.poorGustKn = 25,
    this.partlyWindKn = 20,
    this.partlyGustKn = 30,
    this.strongWindKn = 20,
    this.strongGustKn = 25,
  });

  /// Wind from an exposed sector at or above this is a problem.
  final double minWindKn;

  /// …and at or above these it is a reason to move ("poor").
  final double poorWindKn;
  final double poorGustKn;

  /// Wind / gusts from a partly open sector worth a caution.
  final double partlyWindKn;
  final double partlyGustKn;

  /// Without shelter data: strong wind or gusts → caution.
  final double strongWindKn;
  final double strongGustKn;
}

/// One forecast hour of the timeline.
class HourExposure {
  const HourExposure({
    required this.time,
    this.windKn,
    this.gustKn,
    this.dirDeg,
    this.rating,
    this.fetchM,
    this.risk = HourRisk.none,
  });

  /// Start of the hour, UTC.
  final DateTime time;
  final double? windKn;
  final double? gustKn;

  /// Wind direction (from).
  final double? dirDeg;

  /// Shelter of the upwind sector (null without shelter data or direction).
  final ShelterRating? rating;
  final double? fetchM;
  final HourRisk risk;
}

/// Consecutive hours of wind from an exposed (or partly open) direction.
class ExposureWindow {
  const ExposureWindow({
    required this.risk,
    required this.start,
    required this.end,
    required this.peakTime,
    required this.peakWindKn,
    required this.peakDirDeg,
    required this.fetchM,
    this.maxGustKn,
    this.severe = false,
  });

  final HourRisk risk;

  /// First hour, and the end of the last hour (UTC).
  final DateTime start;
  final DateTime end;
  final DateTime peakTime;
  final double peakWindKn;
  final double peakDirDeg;
  final double? maxGustKn;

  /// Upwind fetch at the peak, metres.
  final double fetchM;

  /// Strong enough to recommend another anchorage.
  final bool severe;
}

/// Result of the anchorage check: shelter + forecast.
class AnchorageAssessment {
  const AnchorageAssessment({
    required this.summary,
    required this.advice,
    this.rating,
    this.exposure,
    this.hours = const [],
    this.windows = const [],
    this.hasForecast = false,
  });

  /// Null when there is not enough data to judge (no forecast).
  final AnchorageRating? rating;

  /// One line for the collapsed card.
  final String summary;

  /// Lines for the expanded card (shelter, exposure windows).
  final List<String> advice;
  final ExposureProfile? exposure;

  /// The next hours, with the upwind shelter of each.
  final List<HourExposure> hours;
  final List<ExposureWindow> windows;
  final bool hasForecast;
}

String _kn(double v) => '${v.round()} kn';

/// Combines the shelter [exposure] (may be null: no land mask) with the
/// [forecast] (may be null) for the next [horizon] from [now].
AnchorageAssessment assessAnchorage({
  required ExposureProfile? exposure,
  required Forecast? forecast,
  required DateTime now,
  Duration horizon = const Duration(hours: 24),
  AssessmentThresholds thresholds = const AssessmentThresholds(),
  TimeFormatter formatTime = defaultTimeFormat,
}) {
  now = now.toUtc();
  final hourStart = DateTime.utc(now.year, now.month, now.day, now.hour);
  final end = now.add(horizon);
  final raw = [
    for (final h in forecast?.hourly ?? const <HourlyWeather>[])
      if (!h.time.isBefore(hourStart) && h.time.isBefore(end)) h,
  ];

  // Per-hour exposure.
  final hours = <HourExposure>[];
  for (final h in raw) {
    final w = h.windKn, g = h.gustKn, d = h.windDirDeg;
    WindExposure? we;
    if (exposure != null && d != null) we = exposure.forWindFrom(d);
    var risk = HourRisk.none;
    if (we != null && w != null) {
      if (we.rating == ShelterRating.exposed && w >= thresholds.minWindKn) {
        risk = HourRisk.exposed;
      } else if (we.rating == ShelterRating.partly &&
          (w >= thresholds.partlyWindKn || (g ?? 0) >= thresholds.partlyGustKn)) {
        risk = HourRisk.partly;
      }
    }
    hours.add(HourExposure(
      time: h.time,
      windKn: w,
      gustKn: g,
      dirDeg: d,
      rating: we?.rating,
      fetchM: we?.fetchM,
      risk: risk,
    ));
  }

  // Group consecutive risky hours of the same kind.
  final windows = <ExposureWindow>[];
  var i = 0;
  while (i < hours.length) {
    final r = hours[i].risk;
    if (r == HourRisk.none) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < hours.length &&
        hours[j + 1].risk == r &&
        hours[j + 1].time.difference(hours[j].time) <= const Duration(hours: 1)) {
      j++;
    }
    final span = hours.sublist(i, j + 1);
    final peak = span.reduce((a, b) => (b.windKn ?? 0) > (a.windKn ?? 0) ? b : a);
    final gusts = [for (final h in span) ?h.gustKn];
    final maxGust = gusts.isEmpty ? null : gusts.reduce(math.max);
    windows.add(ExposureWindow(
      risk: r,
      start: span.first.time,
      end: span.last.time.add(const Duration(hours: 1)),
      peakTime: peak.time,
      peakWindKn: peak.windKn ?? 0,
      peakDirDeg: peak.dirDeg ?? 0,
      fetchM: peak.fetchM ?? 0,
      maxGustKn: maxGust,
      severe: r == HourRisk.exposed &&
          ((peak.windKn ?? 0) >= thresholds.poorWindKn ||
              (maxGust ?? 0) >= thresholds.poorGustKn),
    ));
    i = j + 1;
  }

  final hasForecast = hours.isNotEmpty;
  final advice = <String>[];
  if (exposure != null) advice.add(exposure.describe());

  for (final w in windows) {
    final dir = compass16Name(w.peakDirDeg);
    final when = '${formatTime(w.start)}–${formatTime(w.end)}';
    final gust = w.maxGustKn != null && w.maxGustKn! >= w.peakWindKn + 5
        ? ', gusts ${_kn(w.maxGustKn!)}'
        : '';
    if (w.risk == HourRisk.exposed) {
      advice.add('Exposed to $dir (fetch ${formatFetch(w.fetchM)}): '
          '$dir ${_kn(w.peakWindKn)}$gust expected $when — '
          '${w.severe ? 'consider another anchorage.' : 'expect chop.'}');
    } else {
      advice.add('Partly open to $dir (fetch ${formatFetch(w.fetchM)}): '
          '$dir ${_kn(w.peakWindKn)}$gust expected $when — expect some chop.');
    }
  }

  final winds = [for (final h in hours) if (h.windKn != null) h];
  final maxWindHour =
      winds.isEmpty ? null : winds.reduce((a, b) => b.windKn! > a.windKn! ? b : a);
  final gustList = [for (final h in hours) ?h.gustKn];
  final maxGust = gustList.isEmpty ? null : gustList.reduce(math.max);

  if (exposure != null && hasForecast && windows.isEmpty) {
    advice.add('No wind of ${_kn(thresholds.minWindKn)} or more from an exposed '
        'direction in the next ${horizon.inHours} h.');
  }

  AnchorageRating? rating;
  String summary;
  if (exposure != null && hasForecast) {
    if (windows.any((w) => w.severe)) {
      rating = AnchorageRating.poor;
    } else if (windows.isNotEmpty) {
      rating = AnchorageRating.caution;
    } else {
      rating = AnchorageRating.good;
    }
    if (windows.isNotEmpty) {
      // The worst window: severe first, then exposed, then the strongest.
      final worst = windows.reduce((a, b) {
        int score(ExposureWindow w) => (w.severe ? 2 : 0) + (w.risk == HourRisk.exposed ? 1 : 0);
        final sa = score(a), sb = score(b);
        if (sa != sb) return sb > sa ? b : a;
        return b.peakWindKn > a.peakWindKn ? b : a;
      });
      final dir = compass16Name(worst.peakDirDeg);
      final g = worst.maxGustKn;
      final gustTxt = g != null && g >= worst.peakWindKn + 5 ? ' gusts ${_kn(g)}' : ' ${_kn(worst.peakWindKn)}';
      summary = worst.risk == HourRisk.exposed
          ? 'Exposed to $dir$gustTxt at ${formatTime(worst.peakTime)}'
          : 'Some chop: $dir ${_kn(worst.peakWindKn)} at ${formatTime(worst.peakTime)}';
    } else if (maxWindHour != null && maxWindHour.windKn! >= thresholds.minWindKn) {
      final dir = maxWindHour.dirDeg == null ? '' : '${compass16Name(maxWindHour.dirDeg!)} ';
      summary = 'Good shelter for the forecast $dir${_kn(maxWindHour.windKn!)}';
    } else {
      final max = maxWindHour?.windKn;
      summary = max == null
          ? 'Good shelter for the forecast'
          : 'Light winds (max ${_kn(max)}) — good for the next ${horizon.inHours} h';
    }
  } else if (exposure != null) {
    final open = describeSectorRanges([
      for (final s in exposure.sectors) if (s.rating == ShelterRating.exposed) s.index,
    ]);
    summary = open.isEmpty
        ? 'Well sheltered (no forecast)'
        : 'Open to $open (no forecast)';
  } else if (hasForecast) {
    final strong = (maxWindHour?.windKn ?? 0) >= thresholds.strongWindKn ||
        (maxGust ?? 0) >= thresholds.strongGustKn;
    if (strong) rating = AnchorageRating.caution;
    final parts = <String>[];
    if (maxWindHour != null) {
      final dir = maxWindHour.dirDeg == null ? '' : '${compass16Name(maxWindHour.dirDeg!)} ';
      parts.add('${dir}up to ${_kn(maxWindHour.windKn!)}');
    }
    if (maxGust != null) parts.add('gusts ${_kn(maxGust)}');
    summary = 'No shelter data · ${parts.isEmpty ? 'forecast available' : parts.join(', ')}';
    advice.add('Shelter could not be analysed (no land data for this area or offline). '
        'Check the chart for open directions.');
  } else {
    summary = 'No shelter or forecast data';
  }

  return AnchorageAssessment(
    rating: rating,
    summary: summary,
    advice: advice,
    exposure: exposure,
    hours: hours,
    windows: windows,
    hasForecast: hasForecast,
  );
}
