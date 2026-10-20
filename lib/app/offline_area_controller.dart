import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../domain/geo.dart';
import '../services/map/offline_area.dart';
import '../services/map/offline_area_history.dart';
import '../services/map/tile_cache.dart';
import 'providers.dart';
import 'watch_controller.dart';

// ---- State ------------------------------------------------------------------

/// State of the automatic / "around me" offline chart download.
sealed class OfflineAreaState {
  const OfflineAreaState();
}

class OfflineAreaIdle extends OfflineAreaState {
  const OfflineAreaIdle();
}

class OfflineAreaDownloading extends OfflineAreaState {
  const OfflineAreaDownloading(this.done, this.total, {required this.auto});
  final int done;
  final int total;

  /// Started by a watch (cancelled when the watch stops).
  final bool auto;

  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
  int get percent => (fraction * 100).floor();
}

class OfflineAreaDone extends OfflineAreaState {
  const OfflineAreaDone({
    required this.failed,
    required this.tiles,
    required this.when,
    required this.auto,
  });

  /// Tiles that could not be downloaded.
  final int failed;
  final int tiles;
  final DateTime when;
  final bool auto;
}

enum OfflineSkipReason { unsupported, noPosition, noLayers, recent, busy, nothingToDo }

class OfflineAreaSkipped extends OfflineAreaState {
  const OfflineAreaSkipped(this.kind, this.reason);
  final OfflineSkipReason kind;
  final String reason;
}

class OfflineAreaError extends OfflineAreaState {
  const OfflineAreaError(this.message, {required this.auto});
  final String message;
  final bool auto;
}

// ---- Providers ----------------------------------------------------------------

/// Whether tiles can be downloaded on this platform (false on the web).
final offlineDownloadSupportedProvider = Provider<bool>((ref) => TileDownloader.supported);

/// Layers saved for offline use: everything currently shown on the chart.
final offlineLayersProvider = Provider<List<TileLayerSpec>>(
  (ref) => activeTileLayers(ref.watch(settingsProvider)),
);

/// Remembers recently downloaded areas (a json file in the tile cache).
final offlineAreaHistoryProvider = Provider<OfflineAreaHistory>(
  (ref) => createOfflineAreaHistory(ref.watch(tileCacheProvider)),
);

final offlineAreaPlannerProvider = Provider<OfflineAreaPlanner>(
  (ref) => OfflineAreaPlanner(maxTiles: ref.watch(tileDownloaderProvider).maxTiles),
);

final offlineAreaProvider =
    NotifierProvider<OfflineAreaController, OfflineAreaState>(OfflineAreaController.new);

// ---- Controller ---------------------------------------------------------------

/// Downloads the chart around the anchor when a watch starts (if enabled) and
/// around the boat on request. Runs on its own: failures are logged and shown
/// in [state] but never reach the anchor watch.
class OfflineAreaController extends Notifier<OfflineAreaState> {
  /// An area downloaded within [recentWindow] whose centre is within
  /// [sameAreaM] is not downloaded again automatically.
  static const sameAreaM = 500.0;
  static const recentWindow = Duration(days: 7);
  static const _keepRecords = 20;

  TileDownloadCancelToken? _cancel;
  bool _runningAuto = false;

  @override
  OfflineAreaState build() {
    ref.listen<String?>(watchControllerProvider.select((s) => s.session?.id), (prev, next) {
      try {
        if (prev == null && next != null) {
          _onWatchStarted();
        } else if (prev != null && next == null) {
          _onWatchStopped();
        }
      } catch (e, st) {
        _log('watch listener', e, st);
      }
    });
    ref.onDispose(() => _cancel?.cancel());
    return const OfflineAreaIdle();
  }

  bool get downloading => state is OfflineAreaDownloading;

  int _external = 0;

  /// Whether any chart download runs (this one or "download this area").
  bool get busy => downloading || _external > 0;

  /// The manual "download this map area" flow is running: automatic
  /// downloads wait (are skipped) so at most 2 requests run in parallel.
  void externalStarted() => _external++;
  void externalEnded() => _external = _external > 0 ? _external - 1 : 0;

  void _onWatchStarted() {
    if (!ref.read(settingsProvider).autoOfflineMap) return;
    if (!ref.read(offlineDownloadSupportedProvider)) {
      state = const OfflineAreaSkipped(
          OfflineSkipReason.unsupported, 'Offline charts are not available here.');
      return;
    }
    final anchor = ref.read(watchControllerProvider).session?.anchor;
    if (anchor == null) return;
    unawaited(_run(anchor, auto: true));
  }

  void _onWatchStopped() {
    if (_runningAuto) cancel();
  }

  /// Downloads the chart around the boat's current position now. Completes
  /// when the download finished (or was skipped); [state] tells the result
  /// and is already [OfflineAreaDownloading] or [OfflineAreaSkipped] when
  /// this returns its future.
  Future<OfflineAreaState> downloadAroundMe() {
    if (!ref.read(offlineDownloadSupportedProvider)) {
      return Future.value(state = const OfflineAreaSkipped(
          OfflineSkipReason.unsupported, 'Offline charts are not available here.'));
    }
    final w = ref.read(watchControllerProvider);
    final pos = w.snapshot?.position ?? w.fix?.position;
    if (pos == null) {
      return Future.value(state = const OfflineAreaSkipped(
          OfflineSkipReason.noPosition, 'No GPS position yet.'));
    }
    return _run(pos, auto: false);
  }

  /// Stops the running download (tiles already saved are kept).
  void cancel() => _cancel?.cancel();

  /// Rough size of the automatic download with the current layers.
  int estimateBytes(LatLng centre) {
    try {
      return ref
          .read(offlineAreaPlannerProvider)
          .plan(centre, ref.read(offlineLayersProvider))
          .estimatedBytes;
    } catch (_) {
      return 0;
    }
  }

  Future<OfflineAreaState> _run(LatLng centre, {required bool auto}) async {
    if (busy) return _busy();
    TileDownloadCancelToken? token;
    try {
      final layers = ref.read(offlineLayersProvider);
      if (layers.isEmpty) {
        return state = const OfflineAreaSkipped(
            OfflineSkipReason.noLayers, 'No map layers are switched on.');
      }
      final plan = ref.read(offlineAreaPlannerProvider).plan(centre, layers);
      if (plan.isEmpty) {
        return state = const OfflineAreaSkipped(
            OfflineSkipReason.nothingToDo, 'Nothing to download.');
      }
      final keys = [for (final l in layers) l.key];
      final history = ref.read(offlineAreaHistoryProvider);
      if (auto && await _recentlyDone(history, centre, keys)) {
        if (!ref.mounted) return const OfflineAreaIdle();
        return state = const OfflineAreaSkipped(
            OfflineSkipReason.recent, 'The chart around here was saved recently.');
      }
      if (!ref.mounted) return const OfflineAreaIdle();
      if (busy) return _busy();
      token = _cancel = TileDownloadCancelToken();
      _runningAuto = auto;
      final total = plan.totalTiles;
      state = OfflineAreaDownloading(0, total, auto: auto);


      final downloader = ref.read(tileDownloaderProvider);
      var offset = 0;
      var failed = 0;
      for (final r in plan.requests) {
        if (token.isCancelled || !ref.mounted) break;
        if (r.tiles == 0) continue;
        final base = offset;
        failed += await downloader.downloadArea(
          bounds: r.bounds,
          minZoom: r.minZoom,
          maxZoom: r.maxZoom,
          layers: r.layers,
          cancel: token,
          onProgress: (done, _) {
            if (ref.mounted && !token!.isCancelled) {
              state = OfflineAreaDownloading(base + done, total, auto: auto);
            }
          },
        );
        offset += r.tiles;
      }
      if (!ref.mounted) return const OfflineAreaIdle();
      if (token.isCancelled) return state = const OfflineAreaIdle();
      if (failed >= total) {
        return state = OfflineAreaError(
            'Could not download the chart — no internet?', auto: auto);
      }
      final now = clock.now();
      // A few failed tiles: retry next time (fresh tiles are skipped anyway).
      if (failed <= total ~/ 100) {
        await _remember(history, OfflineAreaRecord(
            centre: centre, completedAt: now, layerKeys: keys));
      }
      if (!ref.mounted) return const OfflineAreaIdle();
      return state = OfflineAreaDone(failed: failed, tiles: total, when: now, auto: auto);
    } catch (e, st) {
      _log('download', e, st);
      if (!ref.mounted) return const OfflineAreaIdle();
      return state = OfflineAreaError('$e', auto: auto);
    } finally {
      if (identical(_cancel, token) && token != null) {
        _cancel = null;
        _runningAuto = false;
      }
    }
  }

  OfflineAreaState _busy() {
    const s = OfflineAreaSkipped(OfflineSkipReason.busy, 'A chart download is already running.');
    // Keep showing the running download's progress.
    if (!downloading) state = s;
    return s;
  }

  Future<bool> _recentlyDone(
      OfflineAreaHistory history, LatLng centre, List<String> keys) async {
    final now = clock.now();
    for (final r in await history.load()) {
      if (now.difference(r.completedAt) < recentWindow &&
          distanceM(r.centre, centre) <= sameAreaM &&
          keys.every(r.layerKeys.contains)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _remember(OfflineAreaHistory history, OfflineAreaRecord rec) async {
    final now = clock.now();
    final kept = (await history.load())
        .where((r) => now.difference(r.completedAt) < recentWindow)
        .toList()
      ..add(rec);
    if (kept.length > _keepRecords) kept.removeRange(0, kept.length - _keepRecords);
    await history.save(kept);
  }

  void _log(String what, Object e, StackTrace st) =>
      debugPrint('OfflineAreaController $what failed: $e\n$st');
}
