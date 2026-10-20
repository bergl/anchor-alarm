import 'weather.dart';

/// Kinds of forecast alerts, in display order.
enum WeatherAlertKind { strongGusts, strongWind, windShift, highWaves, pressureDrop }

/// Something in the forecast worth waking up for. Informational only — never
/// the drag alarm.
class WeatherAlert {
  const WeatherAlert({
    required this.kind,
    required this.time,
    required this.value,
    required this.message,
    this.peakTime,
    this.fromDeg,
    this.toDeg,
  });

  final WeatherAlertKind kind;

  /// Onset (UTC): first forecast hour at or over the threshold; for a wind
  /// shift the hour the new direction is reached; for a pressure drop the
  /// start of the first 3-hour window falling by the threshold.
  final DateTime time;

  /// Peak value: gust/wind kn, wave m, shift degrees, pressure drop hPa.
  final double value;

  /// When [value] is reached (UTC).
  final DateTime? peakTime;

  /// Wind direction (from) at the peak / before a shift; after a shift.
  final double? fromDeg;
  final double? toDeg;
  final String message;

  @override
  String toString() => 'WeatherAlert(${kind.name} $time $value: $message)';
}

/// Alert thresholds (from the settings).
class WeatherThresholds {
  const WeatherThresholds({
    this.gustWarnKn = 25,
    this.windWarnKn = 20,
    this.waveWarnM = 1.5,
  });

  final double gustWarnKn;
  final double windWarnKn;
  final double waveWarnM;

  /// A wind shift counts when the direction changes by more than this…
  static const shiftDeg = 60.0;

  /// …within this time…
  static const shiftWithin = Duration(hours: 6);

  /// …while the wind blows at least this hard (both before and after).
  static const shiftMinWindKn = 10.0;

  /// Pressure falling this much in [pressureWindow] is a storm sign.
  static const pressureDropHpa = 3.0;
  static const pressureWindow = Duration(hours: 3);
}

/// A value and when it occurs.
class Peak {
  const Peak(this.value, this.time, {this.dirDeg});
  final double value;
  final DateTime time;
  final double? dirDeg;
}

class WindShift {
  const WindShift({
    required this.start,
    required this.time,
    required this.fromDeg,
    required this.toDeg,
    required this.windKn,
  });

  /// Hour with the old direction, and the hour the new one is reached.
  final DateTime start;
  final DateTime time;
  final double fromDeg;
  final double toDeg;

  /// Wind at [time].
  final double windKn;

  /// Signed change, −180…180; positive = clockwise (veering).
  double get changeDeg => signedAngleDiff(fromDeg, toDeg);
  bool get veers => changeDeg > 0;
}

class PressureDrop {
  const PressureDrop({required this.start, required this.dropHpa, required this.onset});

  /// Start of the 3-hour window with the largest fall.
  final DateTime start;
  final double dropHpa;

  /// Start of the first window falling at least the threshold.
  final DateTime onset;
}

/// What the next hours look like, from a [Forecast].
class WeatherRisk {
  const WeatherRisk({
    required this.now,
    required this.current,
    required this.hours,
    this.maxGust,
    this.maxWind,
    this.windShift,
    this.maxWave,
    this.pressureDrop,
    this.alerts = const [],
  });

  final DateTime now;

  /// Current conditions: the forecast's "current" block if recent, otherwise
  /// the forecast hour containing [now]. Null when the forecast is over.
  final WeatherConditions? current;

  /// Hours analysed (the next [horizon]).
  final List<WeatherConditions> hours;
  final Peak? maxGust;
  final Peak? maxWind;
  final WindShift? windShift;
  final Peak? maxWave;
  final PressureDrop? pressureDrop;
  final List<WeatherAlert> alerts;

  bool get hasAlerts => alerts.isNotEmpty;
}

/// Formats a time for messages; local "HH:mm" by default.
typedef TimeFormatter = String Function(DateTime t);

String defaultTimeFormat(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// 8-point compass name for a direction in degrees.
String compassPoint(double deg) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return names[((deg % 360 + 22.5) % 360) ~/ 45];
}

/// b − a in degrees, normalised to (−180, 180].
double signedAngleDiff(double a, double b) {
  var d = (b - a) % 360;
  if (d > 180) d -= 360;
  return d;
}

String _kn(double v) => '${v.round()} kn';

/// Analyses the next [horizon] of [f] as seen at [now].
WeatherRisk analyzeWeather(
  Forecast f,
  DateTime now, {
  WeatherThresholds thresholds = const WeatherThresholds(),
  Duration horizon = const Duration(hours: 24),
  TimeFormatter formatTime = defaultTimeFormat,
}) {
  now = now.toUtc();
  final hourStart = DateTime.utc(now.year, now.month, now.day, now.hour);
  final end = now.add(horizon);
  final hours = [
    for (final h in f.hourly)
      if (!h.time.isBefore(hourStart) && h.time.isBefore(end)) h,
  ];

  // Current: "current" block when within the last hour, else this hour.
  WeatherConditions? current;
  final c = f.current;
  if (c != null && !c.time.isAfter(now.add(const Duration(minutes: 30))) &&
      now.difference(c.time) <= const Duration(hours: 1)) {
    current = c;
    // Waves are only hourly.
    final h = hours.isEmpty ? null : hours.first;
    if (h != null && h.waveHeightM != null) {
      current = c.withWaves(heightM: h.waveHeightM, dirDeg: h.waveDirDeg, periodS: h.wavePeriodS);
    }
  } else if (hours.isNotEmpty && !hours.first.time.isAfter(now)) {
    current = hours.first;
  }

  Peak? peakOf(double? Function(WeatherConditions) v) {
    Peak? best;
    for (final h in hours) {
      final x = v(h);
      if (x != null && (best == null || x > best.value)) {
        best = Peak(x, h.time, dirDeg: h.windDirDeg);
      }
    }
    return best;
  }

  final maxGust = peakOf((h) => h.gustKn);
  final maxWind = peakOf((h) => h.windKn);
  final maxWave = peakOf((h) => h.waveHeightM);
  final shift = findWindShift(hours);
  final drop = findPressureDrop(f.hourly, from: hourStart.subtract(
      WeatherThresholds.pressureWindow), until: end);

  final alerts = <WeatherAlert>[];

  /// First hour at/over [limit] and the peak.
  WeatherAlert? exceed(WeatherAlertKind kind, double? Function(WeatherConditions) v,
      double limit, Peak? peak, String Function(Peak p, DateTime onset) message) {
    if (peak == null || peak.value < limit) return null;
    final onset = hours.firstWhere((h) => (v(h) ?? double.negativeInfinity) >= limit);
    return WeatherAlert(
      kind: kind,
      time: onset.time,
      value: peak.value,
      peakTime: peak.time,
      fromDeg: peak.dirDeg,
      message: message(peak, onset.time),
    );
  }

  String from(Peak p) => p.dirDeg == null ? '' : ' from ${compassPoint(p.dirDeg!)}';
  String since(Peak p, DateTime onset, double limit) =>
      onset == p.time || !onset.isAfter(now)
          ? ''
          : ' (over ${limit.round()} kn from ${formatTime(onset)})';

  final g = thresholds.gustWarnKn;
  final gusts = exceed(WeatherAlertKind.strongGusts, (h) => h.gustKn, g, maxGust,
      (p, onset) => 'Gusts to ${_kn(p.value)} expected around '
          '${formatTime(p.time)}${from(p)}${since(p, onset, g)}');
  if (gusts != null) alerts.add(gusts);

  final w = thresholds.windWarnKn;
  final wind = exceed(WeatherAlertKind.strongWind, (h) => h.windKn, w, maxWind,
      (p, onset) => 'Wind ${_kn(p.value)} expected around '
          '${formatTime(p.time)}${from(p)}${since(p, onset, w)}');
  if (wind != null) alerts.add(wind);

  if (shift != null) {
    alerts.add(WeatherAlert(
      kind: WeatherAlertKind.windShift,
      time: shift.time,
      value: shift.changeDeg.abs(),
      fromDeg: shift.fromDeg,
      toDeg: shift.toDeg,
      message: 'Wind ${shift.veers ? 'veers' : 'backs'} '
          '${compassPoint(shift.fromDeg)} → ${compassPoint(shift.toDeg)} '
          'around ${formatTime(shift.time)}, ${_kn(shift.windKn)} — '
          'the boat will swing to a new side of the anchor',
    ));
  }

  final m = thresholds.waveWarnM;
  if (maxWave != null && maxWave.value >= m) {
    final onset = hours.firstWhere((h) => (h.waveHeightM ?? 0) >= m);
    alerts.add(WeatherAlert(
      kind: WeatherAlertKind.highWaves,
      time: onset.time,
      value: maxWave.value,
      peakTime: maxWave.time,
      message: 'Waves to ${maxWave.value.toStringAsFixed(1)} m expected '
          'around ${formatTime(maxWave.time)}',
    ));
  }

  if (drop != null) {
    alerts.add(WeatherAlert(
      kind: WeatherAlertKind.pressureDrop,
      time: drop.onset,
      value: drop.dropHpa,
      peakTime: drop.start,
      message: 'Pressure falling ${drop.dropHpa.toStringAsFixed(1)} hPa in 3 h '
          'from ${formatTime(drop.start)} — possible squalls or a storm',
    ));
  }

  return WeatherRisk(
    now: now,
    current: current,
    hours: hours,
    maxGust: maxGust,
    maxWind: maxWind,
    windShift: shift,
    maxWave: maxWave,
    pressureDrop: drop,
    alerts: alerts,
  );
}

/// First significant wind shift in [hours]: direction changes by more than
/// [WeatherThresholds.shiftDeg] within [WeatherThresholds.shiftWithin], with
/// at least [WeatherThresholds.shiftMinWindKn] at both ends.
WindShift? findWindShift(List<WeatherConditions> hours) {
  bool windy(WeatherConditions h) =>
      h.windDirDeg != null &&
      h.windKn != null &&
      h.windKn! >= WeatherThresholds.shiftMinWindKn;
  for (var i = 0; i < hours.length; i++) {
    final a = hours[i];
    if (!windy(a)) continue;
    for (var j = i + 1; j < hours.length; j++) {
      final b = hours[j];
      if (b.time.difference(a.time) > WeatherThresholds.shiftWithin) break;
      if (!windy(b)) continue;
      if (signedAngleDiff(a.windDirDeg!, b.windDirDeg!).abs() > WeatherThresholds.shiftDeg) {
        return WindShift(
          start: a.time,
          time: b.time,
          fromDeg: a.windDirDeg!,
          toDeg: b.windDirDeg!,
          windKn: b.windKn!,
        );
      }
    }
  }
  return null;
}

/// Largest 3-hour pressure fall in windows starting in [from, until) when it
/// reaches [WeatherThresholds.pressureDropHpa].
PressureDrop? findPressureDrop(List<WeatherConditions> hourly,
    {required DateTime from, required DateTime until}) {
  final byTime = {
    for (final h in hourly)
      if (h.pressureHpa != null) h.time: h.pressureHpa!,
  };
  DateTime? onset;
  DateTime? bestStart;
  var best = 0.0;
  for (final h in hourly) {
    if (h.time.isBefore(from) || !h.time.isBefore(until)) continue;
    final p0 = byTime[h.time];
    final p1 = byTime[h.time.add(WeatherThresholds.pressureWindow)];
    if (p0 == null || p1 == null) continue;
    // Rounded to 0.01 hPa so 1015.0 → 1012.0 counts as exactly 3.
    final drop = ((p0 - p1) * 100).roundToDouble() / 100;
    if (drop >= WeatherThresholds.pressureDropHpa) {
      onset ??= h.time;
      if (drop > best) {
        best = drop;
        bestStart = h.time;
      }
    }
  }
  if (onset == null) return null;
  return PressureDrop(start: bestStart!, dropHpa: best, onset: onset);
}

/// One-line outlook for the Drop anchor panel, e.g.
/// "Next 12 h: wind veers NW→NE, gusts to 24 kn". Null without data.
String? anchoringOutlook(Forecast f, DateTime now,
    {Duration horizon = const Duration(hours: 12)}) {
  final r = analyzeWeather(f, now, horizon: horizon);
  if (r.hours.isEmpty) return null;
  final parts = <String>[];
  final s = r.windShift;
  if (s != null) {
    parts.add('wind ${s.veers ? 'veers' : 'backs'} '
        '${compassPoint(s.fromDeg)}→${compassPoint(s.toDeg)}');
  } else {
    final dirs = [for (final h in r.hours) if (h.windDirDeg != null) h.windDirDeg!];
    final w = r.maxWind;
    if (w != null && dirs.isNotEmpty) {
      parts.add('wind ${compassPoint(dirs.first)} up to ${_kn(w.value)}');
    }
  }
  final g = r.maxGust;
  if (g != null) parts.add('gusts to ${_kn(g.value)}');
  final wave = r.maxWave;
  if (wave != null && wave.value >= 0.5) {
    parts.add('waves to ${wave.value.toStringAsFixed(1)} m');
  }
  if (parts.isEmpty) return null;
  return 'Next ${horizon.inHours} h: ${parts.join(', ')}';
}

/// Compact line for the watch status, e.g.
/// "Wind 12 kn NW · gusts 18 · max 28 kn 03:00". Null without data.
String? weatherSummary(WeatherRisk r, {TimeFormatter formatTime = defaultTimeFormat}) {
  final parts = <String>[];
  final c = r.current;
  if (c != null && c.windKn != null) {
    parts.add('Wind ${_kn(c.windKn!)}'
        '${c.windDirDeg == null ? '' : ' ${compassPoint(c.windDirDeg!)}'}');
    if (c.gustKn != null) parts.add('gusts ${c.gustKn!.round()}');
  }
  final g = r.maxGust;
  if (g != null && (c?.gustKn == null || g.value.round() > c!.gustKn!.round())) {
    parts.add('max ${_kn(g.value)} ${formatTime(g.time)}');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}
