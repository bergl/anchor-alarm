import 'package:latlong2/latlong.dart';

/// Where a position fix came from.
enum FixSource { device, simulated, external }

/// A single position measurement.
class PositionFix {
  const PositionFix({
    required this.position,
    required this.accuracyM,
    required this.time,
    this.speedMps,
    this.courseDeg,
    this.source = FixSource.device,
  });

  final LatLng position;

  /// Horizontal accuracy radius (68 %), metres.
  final double accuracyM;
  final DateTime time;
  final double? speedMps;

  /// Course over ground, degrees. Not the bow heading.
  final double? courseDeg;
  final FixSource source;

  Map<String, Object?> toJson() => {
        'lat': position.latitude,
        'lon': position.longitude,
        'acc': accuracyM,
        't': time.millisecondsSinceEpoch,
        if (speedMps != null) 'spd': speedMps,
        if (courseDeg != null) 'cog': courseDeg,
        'src': source.name,
      };

  factory PositionFix.fromJson(Map<String, Object?> j) => PositionFix(
        position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        accuracyM: (j['acc'] as num).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        speedMps: (j['spd'] as num?)?.toDouble(),
        courseDeg: (j['cog'] as num?)?.toDouble(),
        source: FixSource.values.byName(j['src'] as String? ?? 'device'),
      );
}

/// Alarm sensitivity settings. Built-in profiles are defined in [AlarmProfile.builtIns].
class AlarmProfile {
  const AlarmProfile({
    required this.id,
    required this.name,
    this.builtIn = false,
    this.warningRatio = 0.8,
    this.alarmDelaySec = 10,
    this.averagingSec = 10,
    this.gpsLostSec = 60,
    this.poorAccuracyM = 25,
    this.learnSwing = true,
    this.lowBatteryWarnPct = 20,
    this.lowBatteryAlarmPct = 10,
    this.snoozeSec = 120,
    this.vibrate = true,
    this.sound = 'siren',
  });

  final String id;
  final String name;
  final bool builtIn;

  /// Warning ring radius as a fraction of the alarm radius (0.5–0.95).
  final double warningRatio;

  /// Seconds the boat must stay outside a ring before warning/alarm is raised.
  final int alarmDelaySec;

  /// Position averaging window in seconds (0 = off).
  final int averagingSec;

  /// No usable fix for this long raises the GPS-lost alarm.
  final int gpsLostSec;

  /// Averaged accuracy worse than this (metres) raises the poor-GPS warning.
  final double poorAccuracyM;

  /// Widen the radius (never shrink) during the first minutes of the watch.
  final bool learnSwing;
  final int lowBatteryWarnPct;
  final int lowBatteryAlarmPct;
  final int snoozeSec;
  final bool vibrate;
  final String sound;

  static const lunchId = 'lunch';
  static const overnightId = 'overnight';
  static const stormId = 'storm';

  static const List<AlarmProfile> builtIns = [
    AlarmProfile(
      id: lunchId,
      name: 'Lunch stop',
      builtIn: true,
      alarmDelaySec: 20,
      averagingSec: 15,
      poorAccuracyM: 30,
    ),
    AlarmProfile(id: overnightId, name: 'Overnight', builtIn: true),
    AlarmProfile(
      id: stormId,
      name: 'Storm watch',
      builtIn: true,
      warningRatio: 0.7,
      alarmDelaySec: 5,
      averagingSec: 5,
      gpsLostSec: 30,
      poorAccuracyM: 20,
      learnSwing: false,
      lowBatteryWarnPct: 30,
      lowBatteryAlarmPct: 15,
    ),
  ];

  AlarmProfile copyWith({
    String? id,
    String? name,
    bool? builtIn,
    double? warningRatio,
    int? alarmDelaySec,
    int? averagingSec,
    int? gpsLostSec,
    double? poorAccuracyM,
    bool? learnSwing,
    int? lowBatteryWarnPct,
    int? lowBatteryAlarmPct,
    int? snoozeSec,
    bool? vibrate,
    String? sound,
  }) =>
      AlarmProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        builtIn: builtIn ?? this.builtIn,
        warningRatio: warningRatio ?? this.warningRatio,
        alarmDelaySec: alarmDelaySec ?? this.alarmDelaySec,
        averagingSec: averagingSec ?? this.averagingSec,
        gpsLostSec: gpsLostSec ?? this.gpsLostSec,
        poorAccuracyM: poorAccuracyM ?? this.poorAccuracyM,
        learnSwing: learnSwing ?? this.learnSwing,
        lowBatteryWarnPct: lowBatteryWarnPct ?? this.lowBatteryWarnPct,
        lowBatteryAlarmPct: lowBatteryAlarmPct ?? this.lowBatteryAlarmPct,
        snoozeSec: snoozeSec ?? this.snoozeSec,
        vibrate: vibrate ?? this.vibrate,
        sound: sound ?? this.sound,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'builtIn': builtIn,
        'warningRatio': warningRatio,
        'alarmDelaySec': alarmDelaySec,
        'averagingSec': averagingSec,
        'gpsLostSec': gpsLostSec,
        'poorAccuracyM': poorAccuracyM,
        'learnSwing': learnSwing,
        'lowBatteryWarnPct': lowBatteryWarnPct,
        'lowBatteryAlarmPct': lowBatteryAlarmPct,
        'snoozeSec': snoozeSec,
        'vibrate': vibrate,
        'sound': sound,
      };

  factory AlarmProfile.fromJson(Map<String, Object?> j) {
    const d = AlarmProfile(id: '', name: '');
    return AlarmProfile(
      id: j['id'] as String,
      name: j['name'] as String,
      builtIn: j['builtIn'] as bool? ?? false,
      warningRatio: (j['warningRatio'] as num?)?.toDouble() ?? d.warningRatio,
      alarmDelaySec: j['alarmDelaySec'] as int? ?? d.alarmDelaySec,
      averagingSec: j['averagingSec'] as int? ?? d.averagingSec,
      gpsLostSec: j['gpsLostSec'] as int? ?? d.gpsLostSec,
      poorAccuracyM: (j['poorAccuracyM'] as num?)?.toDouble() ?? d.poorAccuracyM,
      learnSwing: j['learnSwing'] as bool? ?? d.learnSwing,
      lowBatteryWarnPct: j['lowBatteryWarnPct'] as int? ?? d.lowBatteryWarnPct,
      lowBatteryAlarmPct: j['lowBatteryAlarmPct'] as int? ?? d.lowBatteryAlarmPct,
      snoozeSec: j['snoozeSec'] as int? ?? d.snoozeSec,
      vibrate: j['vibrate'] as bool? ?? d.vibrate,
      sound: j['sound'] as String? ?? d.sound,
    );
  }
}

/// Boat dimensions and typical anchoring values; remembered between sessions.
class BoatSettings {
  const BoatSettings({
    this.lengthM = 12,
    this.gpsToBowM = 6,
    this.gpsMarginM = 5,
    this.lastRodeM = 30,
    this.lastDepthM = 5,
  });

  final double lengthM;

  /// Distance from where the phone/GPS usually sits to the bow roller.
  final double gpsToBowM;

  /// Extra radius added for GPS uncertainty.
  final double gpsMarginM;
  final double lastRodeM;
  final double lastDepthM;

  BoatSettings copyWith({
    double? lengthM,
    double? gpsToBowM,
    double? gpsMarginM,
    double? lastRodeM,
    double? lastDepthM,
  }) =>
      BoatSettings(
        lengthM: lengthM ?? this.lengthM,
        gpsToBowM: gpsToBowM ?? this.gpsToBowM,
        gpsMarginM: gpsMarginM ?? this.gpsMarginM,
        lastRodeM: lastRodeM ?? this.lastRodeM,
        lastDepthM: lastDepthM ?? this.lastDepthM,
      );

  Map<String, Object?> toJson() => {
        'lengthM': lengthM,
        'gpsToBowM': gpsToBowM,
        'gpsMarginM': gpsMarginM,
        'lastRodeM': lastRodeM,
        'lastDepthM': lastDepthM,
      };

  factory BoatSettings.fromJson(Map<String, Object?> j) {
    const d = BoatSettings();
    double v(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return BoatSettings(
      lengthM: v('lengthM', d.lengthM),
      gpsToBowM: v('gpsToBowM', d.gpsToBowM),
      gpsMarginM: v('gpsMarginM', d.gpsMarginM),
      lastRodeM: v('lastRodeM', d.lastRodeM),
      lastDepthM: v('lastDepthM', d.lastDepthM),
    );
  }
}

/// Overall watch state, ordered by severity.
enum WatchState { inactive, safe, warning, alarm }

/// Why a warning or alarm is raised. One snapshot can carry several.
enum AlertReason {
  /// Outside the warning ring (but inside the alarm ring).
  nearEdge,

  /// Outside the alarm ring: anchor dragging.
  drag,

  /// No usable position fix for too long.
  gpsLost,

  /// Position accuracy too poor for a reliable watch.
  gpsPoor,
  lowBattery,
  criticalBattery,
}

extension AlertReasonSeverity on AlertReason {
  bool get isAlarm => switch (this) {
        AlertReason.drag || AlertReason.gpsLost || AlertReason.criticalBattery => true,
        _ => false,
      };
}

/// An alert that happened during a session, for the log.
class AlertEvent {
  const AlertEvent({
    required this.reason,
    required this.time,
    this.distanceM,
    this.acknowledgedAt,
  });

  final AlertReason reason;
  final DateTime time;
  final double? distanceM;
  final DateTime? acknowledgedAt;

  AlertEvent copyWith({DateTime? acknowledgedAt}) => AlertEvent(
        reason: reason,
        time: time,
        distanceM: distanceM,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      );

  Map<String, Object?> toJson() => {
        'reason': reason.name,
        't': time.millisecondsSinceEpoch,
        if (distanceM != null) 'd': distanceM,
        if (acknowledgedAt != null) 'ack': acknowledgedAt!.millisecondsSinceEpoch,
      };

  factory AlertEvent.fromJson(Map<String, Object?> j) => AlertEvent(
        reason: AlertReason.values.byName(j['reason'] as String),
        time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        distanceM: (j['d'] as num?)?.toDouble(),
        acknowledgedAt: j['ack'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['ack'] as int),
      );
}

/// One anchoring: the active watch while running, a log entry afterwards.
class AnchorSession {
  const AnchorSession({
    required this.id,
    required this.anchor,
    required this.radiusM,
    required this.initialRadiusM,
    required this.profile,
    required this.startedAt,
    this.endedAt,
    this.rodeM,
    this.depthM,
    this.maxDistanceM = 0,
    this.alerts = const [],
    this.notes = '',
    this.name,
  });

  final String id;
  final LatLng anchor;

  /// Current alarm radius (may have been widened by learn swing or the user).
  final double radiusM;
  final double initialRadiusM;

  /// Snapshot of the profile in use, so the log shows what was active.
  final AlarmProfile profile;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? rodeM;
  final double? depthM;
  final double maxDistanceM;
  final List<AlertEvent> alerts;
  final String notes;

  /// Optional place name entered by the user.
  final String? name;

  bool get isActive => endedAt == null;
  double get warningRadiusM => radiusM * profile.warningRatio;
  Duration duration(DateTime now) => (endedAt ?? now).difference(startedAt);

  AnchorSession copyWith({
    LatLng? anchor,
    double? radiusM,
    double? initialRadiusM,
    AlarmProfile? profile,
    DateTime? endedAt,
    double? rodeM,
    double? depthM,
    double? maxDistanceM,
    List<AlertEvent>? alerts,
    String? notes,
    String? name,
  }) =>
      AnchorSession(
        id: id,
        anchor: anchor ?? this.anchor,
        radiusM: radiusM ?? this.radiusM,
        initialRadiusM: initialRadiusM ?? this.initialRadiusM,
        profile: profile ?? this.profile,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        rodeM: rodeM ?? this.rodeM,
        depthM: depthM ?? this.depthM,
        maxDistanceM: maxDistanceM ?? this.maxDistanceM,
        alerts: alerts ?? this.alerts,
        notes: notes ?? this.notes,
        name: name ?? this.name,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'lat': anchor.latitude,
        'lon': anchor.longitude,
        'radiusM': radiusM,
        'initialRadiusM': initialRadiusM,
        'profile': profile.toJson(),
        'startedAt': startedAt.millisecondsSinceEpoch,
        if (endedAt != null) 'endedAt': endedAt!.millisecondsSinceEpoch,
        if (rodeM != null) 'rodeM': rodeM,
        if (depthM != null) 'depthM': depthM,
        'maxDistanceM': maxDistanceM,
        'alerts': alerts.map((a) => a.toJson()).toList(),
        'notes': notes,
        if (name != null) 'name': name,
      };

  factory AnchorSession.fromJson(Map<String, Object?> j) => AnchorSession(
        id: j['id'] as String,
        anchor: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        radiusM: (j['radiusM'] as num).toDouble(),
        initialRadiusM: (j['initialRadiusM'] as num? ?? j['radiusM'] as num).toDouble(),
        profile: AlarmProfile.fromJson(
            Map<String, Object?>.from(j['profile'] as Map)),
        startedAt: DateTime.fromMillisecondsSinceEpoch(j['startedAt'] as int),
        endedAt: j['endedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['endedAt'] as int),
        rodeM: (j['rodeM'] as num?)?.toDouble(),
        depthM: (j['depthM'] as num?)?.toDouble(),
        maxDistanceM: (j['maxDistanceM'] as num?)?.toDouble() ?? 0,
        alerts: [
          for (final a in (j['alerts'] as List? ?? const []))
            AlertEvent.fromJson(Map<String, Object?>.from(a as Map)),
        ],
        notes: j['notes'] as String? ?? '',
        name: j['name'] as String?,
      );
}

/// A recorded track point (down-sampled).
class TrackPoint {
  const TrackPoint(this.position, this.time, this.accuracyM);

  final LatLng position;
  final DateTime time;
  final double accuracyM;

  Map<String, Object?> toJson() => {
        'lat': position.latitude,
        'lon': position.longitude,
        't': time.millisecondsSinceEpoch,
        'acc': accuracyM,
      };

  factory TrackPoint.fromJson(Map<String, Object?> j) => TrackPoint(
        LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        (j['acc'] as num).toDouble(),
      );
}
