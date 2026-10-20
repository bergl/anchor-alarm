import 'package:intl/intl.dart';

import '../domain/models.dart';
import 'app_settings.dart';

const double _ftPerM = 3.28084;

String formatDistance(double? m, DistanceUnit unit, {int decimals = 0}) {
  if (m == null) return '–';
  return switch (unit) {
    DistanceUnit.metres => '${m.toStringAsFixed(decimals)} m',
    DistanceUnit.feet => '${(m * _ftPerM).toStringAsFixed(decimals)} ft',
  };
}

/// Converts a value entered in [unit] to metres.
double toMetres(double v, DistanceUnit unit) =>
    unit == DistanceUnit.feet ? v / _ftPerM : v;

/// Converts metres to [unit] for display/editing.
double fromMetres(double m, DistanceUnit unit) =>
    unit == DistanceUnit.feet ? m * _ftPerM : m;

String unitSuffix(DistanceUnit unit) => unit == DistanceUnit.feet ? 'ft' : 'm';

String formatBearing(double? deg) {
  if (deg == null) return '–';
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final i = ((deg + 22.5) % 360 ~/ 45);
  return '${deg.round().toString().padLeft(3, '0')}° ${names[i]}';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  final s = d.inSeconds % 60;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

String formatTime(DateTime t) => DateFormat.Hm().format(t);
String formatDateTime(DateTime t) => DateFormat('d MMM y, HH:mm').format(t);

String formatLatLon(double lat, double lon) {
  String f(double v, String pos, String neg) {
    final a = v.abs();
    final d = a.floor();
    final m = (a - d) * 60;
    return '$d°${m.toStringAsFixed(3)}′${v >= 0 ? pos : neg}';
  }

  return '${f(lat, 'N', 'S')} ${f(lon, 'E', 'W')}';
}

String alertTitle(AlertReason r) => switch (r) {
      AlertReason.drag => 'ANCHOR DRAGGING',
      AlertReason.gpsLost => 'GPS signal lost',
      AlertReason.criticalBattery => 'Battery critical',
      AlertReason.nearEdge => 'Approaching alarm ring',
      AlertReason.gpsPoor => 'Poor GPS accuracy',
      AlertReason.lowBattery => 'Battery low',
    };

String alertBody(AlertReason r, {double? distanceM, double? radiusM, DistanceUnit unit = DistanceUnit.metres}) =>
    switch (r) {
      AlertReason.drag =>
        'Boat is ${formatDistance(distanceM, unit)} from the anchor (alarm at ${formatDistance(radiusM, unit)}).',
      AlertReason.nearEdge =>
        'Boat is ${formatDistance(distanceM, unit)} from the anchor (alarm at ${formatDistance(radiusM, unit)}).',
      AlertReason.gpsLost => 'No position fix — the anchor watch cannot see the boat.',
      AlertReason.gpsPoor => 'Position accuracy is poor; alarms may be unreliable.',
      AlertReason.lowBattery => 'Plug the phone in to keep the anchor watch running.',
      AlertReason.criticalBattery => 'Charge now — the anchor watch will stop when the battery dies.',
    };

// ---- UI formatters (appended by the UI) ------------------------------------

/// Short plain-words description of an alert, for the status banner.
String alertShort(AlertReason r) => switch (r) {
      AlertReason.drag => 'Anchor dragging — boat is outside the alarm ring',
      AlertReason.nearEdge => 'Boat is near the edge of the swing circle',
      AlertReason.gpsLost => 'GPS signal lost',
      AlertReason.gpsPoor => 'GPS accuracy is poor',
      AlertReason.lowBattery => 'Battery low — plug the phone in',
      AlertReason.criticalBattery => 'Battery critical — charge now',
    };

/// Big banner word for a watch state.
String stateLabel(WatchState s) => switch (s) {
      WatchState.inactive => 'NOT WATCHING',
      WatchState.safe => 'SAFE',
      WatchState.warning => 'WARNING',
      WatchState.alarm => 'ALARM',
    };

/// GPS accuracy as "±4 m".
String formatAccuracy(double? m, DistanceUnit unit) =>
    m == null ? '–' : '±${formatDistance(m, unit)}';

/// Number only (no unit), converted to [unit], for big displays and inputs.
String formatDistanceValue(double? m, DistanceUnit unit, {int decimals = 0}) =>
    m == null ? '–' : fromMetres(m, unit).toStringAsFixed(decimals);

/// Countdown like "1:45".
String formatCountdown(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// ---- Weather ---------------------------------------------------------------

/// Age of data, e.g. "just now", "25 min ago", "3 h ago", "2 days ago".
String formatAge(Duration d) {
  if (d.inMinutes < 2) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

/// "Forecast from 14:05, 3 h ago".
String formatForecastAge(DateTime fetchedAt, DateTime now) =>
    'Forecast from ${formatTime(fetchedAt.toLocal())}, ${formatAge(now.difference(fetchedAt))}';
