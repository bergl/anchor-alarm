import 'package:latlong2/latlong.dart';

import 'geo.dart';
import 'models.dart';

/// What the user's own log says about a spot.
class HistoryNote {
  const HistoryNote({
    required this.sessions,
    required this.dragAlarms,
    this.lastVisit,
    this.lastDrag,
    this.names = const [],
  });

  /// Finished sessions within the search radius.
  final int sessions;

  /// Sessions with at least one drag alarm.
  final int dragAlarms;
  final DateTime? lastVisit;
  final DateTime? lastDrag;

  /// Place names the user gave those sessions (distinct, newest first).
  final List<String> names;

  /// "You anchored here 2× before, no drag alarms", or null for none.
  String? get text {
    if (sessions == 0) return null;
    final where = names.isEmpty ? 'here' : 'here (${names.first})';
    final drags = dragAlarms == 0
        ? 'no drag alarms'
        : dragAlarms == 1
            ? 'drag alarm once'
            : 'drag alarms $dragAlarms×';
    return 'You anchored $where $sessions× before, $drags';
  }
}

/// Sessions within this distance count as "here".
const historyRadiusM = 500.0;

/// Summarises [history] (finished sessions) within [radiusM] of [point].
HistoryNote historyNear(
  List<AnchorSession> history,
  LatLng point, {
  double radiusM = historyRadiusM,
}) {
  final near = [
    for (final s in history)
      if (!s.isActive && distanceM(s.anchor, point) <= radiusM) s,
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final dragged = [
    for (final s in near)
      if (s.alerts.any((a) => a.reason == AlertReason.drag)) s,
  ];
  final names = <String>[];
  for (final s in near) {
    final n = s.name?.trim();
    if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
  }
  return HistoryNote(
    sessions: near.length,
    dragAlarms: dragged.length,
    lastVisit: near.isEmpty ? null : near.first.startedAt,
    lastDrag: dragged.isEmpty ? null : dragged.first.startedAt,
    names: names,
  );
}
