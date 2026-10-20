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
