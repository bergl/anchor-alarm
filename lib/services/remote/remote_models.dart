import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../../domain/watch_engine.dart';

/// Base of share links. The web app opens `#join=...` links directly.
const shareBaseUrl = String.fromEnvironment(
  'SHARE_BASE_URL',
  defaultValue: 'https://bergl.github.io/anchor-alarm/',
);

/// App version written to the watch document.
const remoteAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

const _base32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const _idChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// 128-bit random share key, RFC 4648 base32 without padding (26 chars).
String newShareKey([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_base32[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// Random 20-character document id (same alphabet as Firestore auto ids).
String newWatchId([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes(
      List.generate(20, (_) => _idChars.codeUnitAt(r.nextInt(_idChars.length))));
}

/// What a share link / code carries: the watch and its share key.
class ShareLink {
  const ShareLink(this.watchId, this.shareKey);

  final String watchId;
  final String shareKey;

  /// "watchId.SHAREKEY" — what is typed or pasted as a code.
  String get code => '$watchId.$shareKey';

  /// `https://bergl.github.io/anchor-alarm/#join=<watchId>.<shareKey>`
  String get url => '$shareBaseUrl#join=$code';

  static final _pattern = RegExp(r'([A-Za-z0-9]{20})\s*\.\s*([A-Za-z2-7][A-Za-z2-7 \-]{25,})');

  /// Parses a full link, a `#join=` fragment or a bare code. Tolerates
  /// surrounding text, lower case and spaces / dashes in the key (codes read
  /// out or typed by hand). Returns null when nothing valid is found.
  static ShareLink? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    final join = RegExp(r'join=([^&\s]+)').firstMatch(text);
    if (join != null) text = Uri.decodeComponent(join.group(1)!);
    final m = _pattern.firstMatch(text);
    if (m == null) return null;
    final key = m.group(2)!.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    if (key.length < 26) return null;
    final k = key.substring(0, 26);
    if (!RegExp(r'^[A-Z2-7]{26}$').hasMatch(k)) return null;
    return ShareLink(m.group(1)!, k);
  }

  @override
  bool operator ==(Object other) =>
      other is ShareLink && other.watchId == watchId && other.shareKey == shareKey;

  @override
  int get hashCode => Object.hash(watchId, shareKey);

  @override
  String toString() => 'ShareLink($code)';
}

/// Sharing state of one local anchor session, kept on the device (keyed by
/// session id) so a restored watch keeps publishing to the same document.
class ShareRecord {
  const ShareRecord({
    required this.sessionId,
    required this.watchId,
    required this.shareKey,
    required this.active,
  });

  final String sessionId;
  final String watchId;
  final String shareKey;

  /// Uploading is on. False after "Stop sharing" or when the watch ended.
  final bool active;

  ShareLink get link => ShareLink(watchId, shareKey);

  ShareRecord copyWith({String? shareKey, bool? active}) => ShareRecord(
        sessionId: sessionId,
        watchId: watchId,
        shareKey: shareKey ?? this.shareKey,
        active: active ?? this.active,
      );

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'watchId': watchId,
        'shareKey': shareKey,
        'active': active,
      };

  factory ShareRecord.fromJson(Map<String, Object?> j) => ShareRecord(
        sessionId: j['sessionId'] as String,
        watchId: j['watchId'] as String,
        shareKey: j['shareKey'] as String,
        active: j['active'] as bool? ?? false,
      );
}

/// A boat this device monitors.
class MonitoredBoat {
  const MonitoredBoat({
    required this.watchId,
    required this.shareKey,
    required this.addedAt,
    this.name,
  });

  final String watchId;
  final String shareKey;
  final DateTime addedAt;

  /// Last boat name seen, for the list.
  final String? name;

  MonitoredBoat copyWith({String? name}) =>
      MonitoredBoat(watchId: watchId, shareKey: shareKey, addedAt: addedAt, name: name ?? this.name);

  Map<String, Object?> toJson() => {
        'watchId': watchId,
        'shareKey': shareKey,
        'addedAt': addedAt.millisecondsSinceEpoch,
        if (name != null) 'name': name,
      };

  factory MonitoredBoat.fromJson(Map<String, Object?> j) => MonitoredBoat(
        watchId: j['watchId'] as String,
        shareKey: j['shareKey'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(j['addedAt'] as int),
        name: j['name'] as String?,
      );
}

/// What the boat writes to `watches/{watchId}` (besides `updatedAt`, which
/// is always the server time).
class RemoteWatchWrite {
  const RemoteWatchWrite({
    required this.ownerUid,
    required this.shareKey,
    required this.boatName,
    required this.anchor,
    required this.radiusM,
    required this.warningRadiusM,
    required this.state,
    required this.reasons,
    required this.ringing,
    required this.startedAt,
    required this.tzOffsetMin,
    this.boat,
    this.accuracyM,
    this.snoozedUntil,
    this.distanceM,
    this.endedAt,
    this.appVersion = remoteAppVersion,
  });

  factory RemoteWatchWrite.from({
    required String ownerUid,
    required String shareKey,
    required String boatName,
    required AnchorSession session,
    WatchSnapshot? snapshot,
    required int tzOffsetMin,
  }) {
    final radius = (snapshot?.radiusM ?? session.radiusM).clamp(1.0, 5000.0).toDouble();
    final warning =
        (snapshot?.warningRadiusM ?? session.warningRadiusM).clamp(0.1, radius).toDouble();
    final name = boatName.trim();
    return RemoteWatchWrite(
      ownerUid: ownerUid,
      shareKey: shareKey,
      boatName: name.length > 60 ? name.substring(0, 60) : name,
      anchor: session.anchor,
      radiusM: radius,
      warningRadiusM: warning,
      boat: snapshot?.position,
      accuracyM: snapshot?.accuracyM,
      state: session.endedAt != null ? WatchState.inactive : snapshot?.state ?? WatchState.safe,
      reasons: session.endedAt != null ? const {} : snapshot?.reasons ?? const {},
      ringing: session.endedAt == null && (snapshot?.ringing ?? false),
      snoozedUntil: snapshot?.snoozedUntil,
      distanceM: snapshot?.distanceM,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      tzOffsetMin: tzOffsetMin,
    );
  }

  final String ownerUid;
  final String shareKey;
  final String boatName;
  final LatLng anchor;
  final double radiusM;
  final double warningRadiusM;
  final LatLng? boat;
  final double? accuracyM;
  final WatchState state;
  final Set<AlertReason> reasons;
  final bool ringing;
  final DateTime? snoozedUntil;
  final double? distanceM;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String appVersion;
  final int tzOffsetMin;

  RemoteWatchWrite copyWith({String? shareKey, DateTime? endedAt, bool? ringing, WatchState? state}) =>
      RemoteWatchWrite(
        ownerUid: ownerUid,
        shareKey: shareKey ?? this.shareKey,
        boatName: boatName,
        anchor: anchor,
        radiusM: radiusM,
        warningRadiusM: warningRadiusM,
        boat: boat,
        accuracyM: accuracyM,
        state: state ?? this.state,
        reasons: reasons,
        ringing: ringing ?? this.ringing,
        snoozedUntil: snoozedUntil,
        distanceM: distanceM,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        appVersion: appVersion,
        tzOffsetMin: tzOffsetMin,
      );

  /// Document fields with times as [DateTime] (the store converts them).
  /// `updatedAt` is added by the store as the server timestamp.
  Map<String, Object?> toFields() => {
        'ownerUid': ownerUid,
        'shareKey': shareKey,
        'boatName': boatName,
        'anchor': {'lat': anchor.latitude, 'lon': anchor.longitude},
        'radiusM': radiusM,
        'warningRadiusM': warningRadiusM,
        'boat': boat == null
            ? null
            : {
                'lat': boat!.latitude,
                'lon': boat!.longitude,
                if (accuracyM != null) 'accuracyM': accuracyM,
              },
        'state': state.name,
        'reasons': [for (final r in AlertReason.values) if (reasons.contains(r)) r.name],
        'ringing': ringing,
        'snoozedUntil': snoozedUntil,
        'distanceM': distanceM,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'appVersion': appVersion,
        'tzOffsetMin': tzOffsetMin,
      };
}

/// Whether [next] differs from what was last sent enough to write now
/// rather than wait for the heartbeat: any change of state, reasons,
/// ringing, snooze, anchor, radius or the end; the boat moving 3 m or more;
/// the distance changing by 2 m or more.
bool isMaterialChange(RemoteWatchWrite prev, RemoteWatchWrite next) {
  if (prev.state != next.state ||
      prev.ringing != next.ringing ||
      prev.snoozedUntil != next.snoozedUntil ||
      prev.endedAt != next.endedAt ||
      prev.shareKey != next.shareKey ||
      prev.boatName != next.boatName ||
      prev.reasons.length != next.reasons.length ||
      !prev.reasons.containsAll(next.reasons)) {
    return true;
  }
  if ((prev.radiusM - next.radiusM).abs() >= 0.5 ||
      (prev.warningRadiusM - next.warningRadiusM).abs() >= 0.5) {
    return true;
  }
  if (distanceM(prev.anchor, next.anchor) >= 0.5) return true;
  final pb = prev.boat, nb = next.boat;
  if ((pb == null) != (nb == null)) return true;
  if (pb != null && nb != null && distanceM(pb, nb) >= 3) return true;
  final pd = prev.distanceM, nd = next.distanceM;
  if ((pd == null) != (nd == null)) return true;
  if (pd != null && nd != null && (pd - nd).abs() >= 2) return true;
  return false;
}

/// A watch as seen by a monitoring device.
class RemoteWatch {
  const RemoteWatch({
    required this.id,
    required this.boatName,
    required this.anchor,
    required this.radiusM,
    required this.warningRadiusM,
    required this.state,
    required this.reasons,
    required this.ringing,
    this.boat,
    this.accuracyM,
    this.snoozedUntil,
    this.distanceM,
    this.updatedAt,
    this.startedAt,
    this.endedAt,
    this.tzOffsetMin,
  });

  final String id;
  final String boatName;
  final LatLng anchor;
  final double radiusM;
  final double warningRadiusM;
  final LatLng? boat;
  final double? accuracyM;
  final WatchState state;
  final Set<AlertReason> reasons;
  final bool ringing;
  final DateTime? snoozedUntil;
  final double? distanceM;

  /// Server time of the boat's last write (null while a local write is pending).
  final DateTime? updatedAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? tzOffsetMin;

  bool get ended => endedAt != null;
  String get displayName => boatName.trim().isEmpty ? 'Boat' : boatName.trim();

  Set<AlertReason> get alarmReasons => reasons.where((r) => r.isAlarm).toSet();

  /// Parses document fields. Times must already be [DateTime] (the store
  /// converts Firestore timestamps). Unknown values degrade gracefully.
  factory RemoteWatch.fromFields(String id, Map<String, Object?> f) {
    LatLng? pos(Object? v) {
      if (v is! Map) return null;
      final lat = v['lat'], lon = v['lon'];
      if (lat is! num || lon is! num) return null;
      return LatLng(lat.toDouble(), lon.toDouble());
    }

    double? numOr(Object? v) => v is num ? v.toDouble() : null;
    DateTime? time(Object? v) => v is DateTime ? v : null;
    final boatMap = f['boat'];
    final reasons = <AlertReason>{
      for (final r in (f['reasons'] is List ? f['reasons'] as List : const []))
        for (final a in AlertReason.values)
          if (a.name == r) a,
    };
    final state = WatchState.values.firstWhere(
      (s) => s.name == f['state'],
      orElse: () => WatchState.safe,
    );
    return RemoteWatch(
      id: id,
      boatName: f['boatName'] is String ? f['boatName'] as String : '',
      anchor: pos(f['anchor']) ?? const LatLng(0, 0),
      radiusM: numOr(f['radiusM']) ?? 50,
      warningRadiusM: numOr(f['warningRadiusM']) ?? numOr(f['radiusM']) ?? 50,
      boat: pos(boatMap),
      accuracyM: boatMap is Map ? numOr(boatMap['accuracyM']) : null,
      state: state,
      reasons: reasons,
      ringing: f['ringing'] == true,
      snoozedUntil: time(f['snoozedUntil']),
      distanceM: numOr(f['distanceM']),
      updatedAt: time(f['updatedAt']),
      startedAt: time(f['startedAt']),
      endedAt: time(f['endedAt']),
      tzOffsetMin: f['tzOffsetMin'] is int ? f['tzOffsetMin'] as int : null,
    );
  }
}

/// How current the monitored data is.
enum Freshness {
  /// Updated within the last 30 s.
  fresh,

  /// 30 s – 3 min without an update (amber).
  stale,

  /// No update for over 3 min: "Lost contact" (red).
  lost,

  /// The boat ended the watch.
  ended,
}

const staleAfter = Duration(seconds: 30);
const lostContactAfter = Duration(minutes: 3);

Freshness freshnessOf(RemoteWatch w, DateTime now) {
  if (w.ended) return Freshness.ended;
  final u = w.updatedAt;
  if (u == null) return Freshness.fresh;
  final age = now.difference(u);
  if (age > lostContactAfter) return Freshness.lost;
  if (age > staleAfter) return Freshness.stale;
  return Freshness.fresh;
}

/// "updated 12 s ago", "updated 4 min ago", "updated 2 h ago".
String updatedAgo(DateTime? updatedAt, DateTime now) {
  if (updatedAt == null) return 'updating…';
  final s = now.difference(updatedAt).inSeconds;
  if (s < 5) return 'updated just now';
  if (s < 60) return 'updated $s s ago';
  final m = s ~/ 60;
  if (m < 60) return 'updated $m min ago';
  final h = m ~/ 60;
  if (h < 48) return 'updated $h h ago';
  return 'updated ${h ~/ 24} days ago';
}

/// "14:05" in the device's local time.
String clockTime(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
