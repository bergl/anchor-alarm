import 'package:flutter_map/flutter_map.dart' show MapCamera;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/providers.dart';
import '../app/watch_controller.dart';
import '../domain/geo.dart';
import '../domain/models.dart';
import '../services/battery/battery_monitor.dart';

/// Live compass heading (null when unavailable).
final headingProvider = StreamProvider<double?>((ref) {
  return ref.watch(headingSourceProvider).heading;
});

/// Latest battery reading (no value on platforms without battery info).
final batteryProvider = StreamProvider<BatteryReading>((ref) {
  return ref.watch(batteryMonitorProvider).readings;
});

/// Turns "keep the screen on" on and off. Overridable in tests.
final screenWakeProvider = Provider<Future<void> Function(bool on)>(
  (ref) => (on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Not supported on this platform / in tests.
    }
  },
);

/// Boat positions of roughly the last hour, kept in memory for the map track.
class RecentTrack extends Notifier<List<LatLng>> {
  static const keep = Duration(hours: 1);
  static const _minStepM = 1.0;
  static const _minInterval = Duration(seconds: 5);

  final List<DateTime> _times = [];
  String? _sessionId;

  @override
  List<LatLng> build() {
    ref.listen<WatchViewState>(watchControllerProvider, (prev, next) {
      final id = next.session?.id;
      if (id != null && id != _sessionId) {
        _sessionId = id;
        _times.clear();
        state = const [];
      }
      final pos = next.snapshot?.position ?? next.fix?.position;
      final t = next.snapshot?.time ?? next.fix?.time;
      if (pos != null && t != null) add(pos, t);
    });
    return const [];
  }

  void add(LatLng p, DateTime t) {
    final pts = List<LatLng>.of(state);
    if (pts.isNotEmpty) {
      final moved = distanceM(pts.last, p);
      final dt = t.difference(_times.last);
      if (moved < _minStepM && dt < _minInterval) return;
      if (dt.isNegative) return;
    }
    pts.add(p);
    _times.add(t);
    final cutoff = t.subtract(keep);
    var drop = 0;
    while (drop < _times.length && _times[drop].isBefore(cutoff)) {
      drop++;
    }
    if (drop > 0) {
      pts.removeRange(0, drop);
      _times.removeRange(0, drop);
    }
    state = pts;
  }
}

final recentTrackProvider =
    NotifierProvider<RecentTrack, List<LatLng>>(RecentTrack.new);

/// Which panel the map screen shows at the bottom.
enum MapPanel { status, dropAnchor }

class MapPanelController extends Notifier<MapPanel> {
  @override
  MapPanel build() => MapPanel.status;
  void show(MapPanel p) => state = p;
}

final mapPanelProvider =
    NotifierProvider<MapPanelController, MapPanel>(MapPanelController.new);

/// Finished sessions, newest first. Invalidate after changes.
final historyProvider = FutureProvider.autoDispose<List<AnchorSession>>(
  (ref) => ref.watch(sessionRepositoryProvider).history(),
);

final trackProvider =
    FutureProvider.autoDispose.family<List<TrackPoint>, String>(
  (ref, id) => ref.watch(sessionRepositoryProvider).track(id),
);

/// Last camera of the main map (for "download this area"). Mutable holder,
/// updated on every map move without rebuilding anything.
class MapViewHolder {
  MapCamera? camera;
}

final mapViewProvider = Provider<MapViewHolder>((ref) => MapViewHolder());

/// Size of the offline tile cache in bytes. Invalidate after downloads/clear.
final tileCacheSizeProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(tileDownloaderProvider).cacheSizeBytes(),
);
