import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../domain/anchorage_assessment.dart';
import '../domain/anchoring_history.dart';
import '../domain/exposure.dart';
import '../domain/geo.dart';
import '../domain/swing_preview.dart';
import '../domain/water_mask.dart';
import '../services/map/anchorage_service.dart';
import '../services/map/depth_service.dart';
import '../services/map/landmask_service.dart';
import 'providers.dart';
import 'watch_controller.dart';
import 'weather_controller.dart';

// ---- Services ----------------------------------------------------------------

/// Land / water raster for the shelter analysis. Overridden in tests.
final landMaskServiceProvider = Provider<LandMaskService>((ref) {
  final s = LandMaskService(store: createLandMaskStore());
  ref.onDispose(s.close);
  return s;
});

/// Nearby anchorages (OSM via Overpass). Overridden in tests.
final anchorageServiceProvider = Provider<AnchorageService>((ref) {
  final s = OverpassAnchorageService();
  ref.onDispose(s.close);
  return s;
});

// ---- State -------------------------------------------------------------------

/// Data gathered for the anchorage check at [point].
class AnchorageCheckState {
  const AnchorageCheckState({
    this.point,
    this.maskLoading = false,
    this.maskUnavailable = false,
    this.exposure,
    this.anchoragesLoading = false,
    this.anchorages,
    this.anchoragesUnavailable = false,
    this.history,
    this.chartedDepth,
    this.expanded = false,
    this.showNearbyOnMap = false,
  });

  /// Position checked (the anchor, or the draft anchor).
  final LatLng? point;
  final bool maskLoading;

  /// No land data (offline, server error).
  final bool maskUnavailable;
  final ExposureProfile? exposure;
  final bool anchoragesLoading;
  final List<NearbyAnchorage>? anchorages;
  final bool anchoragesUnavailable;
  final HistoryNote? history;

  /// Looked up by the check itself when the caller has none.
  final DepthSample? chartedDepth;

  /// The assistant is open: the map draws the exposure rose.
  final bool expanded;
  final bool showNearbyOnMap;

  AnchorageCheckState copyWith({
    LatLng? point,
    bool? maskLoading,
    bool? maskUnavailable,
    ExposureProfile? exposure,
    bool clearExposure = false,
    bool? anchoragesLoading,
    List<NearbyAnchorage>? anchorages,
    bool? anchoragesUnavailable,
    HistoryNote? history,
    DepthSample? chartedDepth,
    bool? expanded,
    bool? showNearbyOnMap,
  }) =>
      AnchorageCheckState(
        point: point ?? this.point,
        maskLoading: maskLoading ?? this.maskLoading,
        maskUnavailable: maskUnavailable ?? this.maskUnavailable,
        exposure: clearExposure ? null : exposure ?? this.exposure,
        anchoragesLoading: anchoragesLoading ?? this.anchoragesLoading,
        anchorages: anchorages ?? this.anchorages,
        anchoragesUnavailable: anchoragesUnavailable ?? this.anchoragesUnavailable,
        history: history ?? this.history,
        chartedDepth: chartedDepth ?? this.chartedDepth,
        expanded: expanded ?? this.expanded,
        showNearbyOnMap: showNearbyOnMap ?? this.showNearbyOnMap,
      );
}

final anchorageCheckProvider =
    NotifierProvider<AnchorageCheckController, AnchorageCheckState>(
        AnchorageCheckController.new);

/// Gathers shelter (land mask → exposure), nearby anchorages, the user's
/// history and (optionally) charted depth for a position. Every source is
/// optional; failures only show up as "unavailable" in the state.
class AnchorageCheckController extends Notifier<AnchorageCheckState> {
  /// Re-analyse the shelter when the point moves this far.
  static const exposureMoveM = 25.0;

  /// Query nearby anchorages again after moving this far.
  static const anchoragesMoveM = 1000.0;

  /// Search radius for nearby anchorages.
  static const anchoragesRadiusM = 5000.0;

  /// Wait this long before asking a failed source again.
  static const retryAfter = Duration(minutes: 2);

  DateTime? _maskFailedAt;
  LatLng? _anchoragesAt;
  DateTime? _anchoragesFailedAt;
  LatLng? _depthAt;
  int _seq = 0;

  @override
  AnchorageCheckState build() => const AnchorageCheckState();

  void setExpanded(bool v) {
    if (ref.mounted && state.expanded != v) state = state.copyWith(expanded: v);
  }

  void setShowNearbyOnMap(bool v) => state = state.copyWith(showNearbyOnMap: v);

  /// Checks [p]. Cheap to call often: work is only done when the point has
  /// moved enough. With [lookupDepth] the charted depth is fetched too (the
  /// Drop anchor panel already has one).
  Future<void> check(LatLng p, {bool lookupDepth = false}) async {
    final prev = state.point;
    final moved = prev == null ? double.infinity : distanceM(prev, p);
    if (moved < exposureMoveM) {
      if (state.maskLoading || state.exposure != null) return;
      final failed = _maskFailedAt;
      if (failed != null && clock.now().difference(failed) < retryAfter) return;
    }
    final seq = ++_seq;
    state = state.copyWith(point: p);
    await Future.wait([
      _guard('mask', () => _checkShelter(p, seq)),
      _guard('anchorages', () => _checkAnchorages(p)),
      _guard('history', () => _checkHistory(p, seq)),
      if (lookupDepth) _guard('depth', () => _checkDepth(p, seq)),
    ]);
  }

  /// Forget failures and fetch again (retry button).
  Future<void> retry() async {
    final p = state.point;
    if (p == null) return;
    _anchoragesFailedAt = null;
    _maskFailedAt = null;
    _anchoragesAt = null;
    state = state.copyWith(maskUnavailable: false, anchoragesUnavailable: false);
    _seq++;
    await Future.wait([
      _guard('mask', () => _checkShelter(p, _seq)),
      _guard('anchorages', () => _checkAnchorages(p)),
    ]);
  }

  Future<void> _checkShelter(LatLng p, int seq) async {
    final svc = ref.read(landMaskServiceProvider);
    final cached = svc.cached(p);
    if (cached != null) {
      state = state.copyWith(
          exposure: computeExposure(cached, p), maskLoading: false, maskUnavailable: false);
      return;
    }
    state = state.copyWith(maskLoading: true);
    final WaterMask? mask = await svc.maskAround(p);
    if (!ref.mounted || seq != _seq) return;
    final exp = mask == null ? null : computeExposure(mask, p);
    _maskFailedAt = exp == null ? clock.now() : null;
    state = state.copyWith(
      maskLoading: false,
      maskUnavailable: exp == null,
      exposure: exp,
      clearExposure: exp == null,
    );
  }

  Future<void> _checkAnchorages(LatLng p) async {
    final last = _anchoragesAt;
    if (last != null && distanceM(last, p) < anchoragesMoveM && state.anchorages != null) {
      // Same area: only distances change.
      state = state.copyWith(anchorages: [
        for (final a in state.anchorages!)
          NearbyAnchorage(
            position: a.position,
            kind: a.kind,
            distanceM: distanceM(p, a.position),
            name: a.name,
            osmId: a.osmId,
          ),
      ]..sort((a, b) => a.distanceM.compareTo(b.distanceM)));
      return;
    }
    final failed = _anchoragesFailedAt;
    if (failed != null && clock.now().difference(failed) < retryAfter) return;
    state = state.copyWith(anchoragesLoading: true);
    final list = await ref.read(anchorageServiceProvider).nearby(p, radiusM: anchoragesRadiusM);
    if (!ref.mounted) return;
    if (list == null) {
      _anchoragesFailedAt = clock.now();
      state = state.copyWith(anchoragesLoading: false, anchoragesUnavailable: true);
    } else {
      _anchoragesAt = p;
      _anchoragesFailedAt = null;
      state = state.copyWith(
          anchoragesLoading: false, anchoragesUnavailable: false, anchorages: list);
    }
  }

  Future<void> _checkHistory(LatLng p, int seq) async {
    final sessions = await ref.read(sessionRepositoryProvider).history();
    if (!ref.mounted || seq != _seq) return;
    state = state.copyWith(history: historyNear(sessions, p));
  }

  Future<void> _checkDepth(LatLng p, int seq) async {
    final last = _depthAt;
    if (last != null && distanceM(last, p) < 25 && state.chartedDepth != null) return;
    _depthAt = p;
    final d = await ref.read(depthServiceProvider).depthAt(p);
    if (!ref.mounted || seq != _seq || d == null) return;
    state = state.copyWith(chartedDepth: d);
  }

  Future<void> _guard(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      debugPrint('AnchorageCheck $what failed: $e\n$st');
    }
  }
}

// ---- Derived -----------------------------------------------------------------

/// Shelter + forecast verdict for the checked point (null before a check).
final anchorageAssessmentProvider = Provider<AnchorageAssessment?>((ref) {
  final c = ref.watch(anchorageCheckProvider);
  if (c.point == null) return null;
  final forecast = ref.watch(weatherControllerProvider.select((w) => w.forecast));
  return assessAnchorage(exposure: c.exposure, forecast: forecast, now: clock.now());
});

/// Where the boat will swing over the next 12 h (draft or watched anchor),
/// for the map. Shown while dropping anchor, and while watching when the
/// anchorage check is open.
final swingPreviewProvider = Provider<SwingPreview?>((ref) {
  final w = ref.watch(watchControllerProvider.select((s) => (
        s.session?.anchor ?? s.draft?.anchor,
        s.session?.rodeM ?? s.draft?.rodeM,
        s.session?.depthM ?? s.draft?.depthM,
        s.watching,
      )));
  final (anchor, rode, depth, watching) = w;
  if (anchor == null || rode == null) return null;
  if (watching && !ref.watch(anchorageCheckProvider.select((c) => c.expanded))) return null;
  final forecast = ref.watch(weatherControllerProvider.select((s) => s.forecast));
  if (forecast == null) return null;
  final r = horizontalRodeM(rodeM: rode, depthM: depth ?? 0);
  if (r <= 0) return null;
  return computeSwingPreview(anchor: anchor, radiusM: r, forecast: forecast, now: clock.now());
});
