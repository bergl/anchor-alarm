import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/providers.dart';
import '../../../app/watch_controller.dart';
import '../../../services/map/depth_service.dart';
import '../../ui_providers.dart';
import 'drop_anchor_model.dart';

class DropAnchorFormController extends Notifier<DropAnchorForm> {
  @override
  DropAnchorForm build() {
    final boat = ref.read(settingsProvider).boat;
    return DropAnchorForm(rodeM: boat.lastRodeM, depthM: boat.lastDepthM);
  }

  /// Fresh form with the remembered rode and depth.
  void reset({AnchorMethod method = AnchorMethod.settled, LatLng? mapAnchor}) {
    final boat = ref.read(settingsProvider).boat;
    state = DropAnchorForm(
      rodeM: boat.lastRodeM,
      depthM: boat.lastDepthM,
      method: method,
      mapAnchor: mapAnchor,
    );
  }

  void update(DropAnchorForm Function(DropAnchorForm) change) => state = change(state);

  /// Depth set by the user (never overwritten by charted depth afterwards).
  void setDepth(double depthM) => state = state.withUserDepth(depthM);

  /// Result of a charted depth lookup at the anchor position.
  void applyChartedDepth(DepthSample? sample) =>
      state = state.withChartedDepth(sample);

  /// Anchor placed or dragged on the map.
  void placeOnMap(LatLng p) =>
      state = state.copyWith(method: AnchorMethod.map, mapAnchor: p);
}

final dropAnchorFormProvider =
    NotifierProvider<DropAnchorFormController, DropAnchorForm>(
        DropAnchorFormController.new);

/// The anchor/radius the form currently describes (null without a position).
final draftPreviewProvider = Provider<AnchorDraft?>((ref) {
  final form = ref.watch(dropAnchorFormProvider);
  final boatSettings = ref.watch(settingsProvider.select((s) => s.boat));
  final fix = ref.watch(watchControllerProvider.select((s) => s.fix));
  final compass = form.method == AnchorMethod.settled
      ? ref.watch(headingProvider).value
      : null;
  final anchor = form.anchor(
    boat: fix?.position,
    compassDeg: compass,
    settings: boatSettings,
  );
  if (anchor == null) return null;
  return AnchorDraft(
    anchor: anchor,
    radiusM: form.radius(boatSettings),
    rodeM: form.rodeM,
    depthM: form.depthM,
  );
});
