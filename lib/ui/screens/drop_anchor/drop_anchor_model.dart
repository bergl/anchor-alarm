import 'package:latlong2/latlong.dart';

import '../../../domain/geo.dart';
import '../../../domain/models.dart';
import '../../../services/map/depth_service.dart';

/// How the anchor position is determined when dropping anchor.
enum AnchorMethod {
  /// Boat has settled; anchor lies ahead of the bow by the horizontal rode.
  settled,

  /// Anchor is at the boat's current position.
  here,

  /// User places it on the map (long-press / drag).
  map,
}

const double minRadiusM = 10;
const double maxRadiusM = 300;

/// Charted depths below this are not used to prefill the depth field.
const double minPrefillDepthM = 1;

/// Inputs of the "Drop anchor" form, all in metres / degrees.
class DropAnchorForm {
  const DropAnchorForm({
    required this.rodeM,
    required this.depthM,
    this.method = AnchorMethod.settled,
    this.manualBowDeg = 0,
    this.radiusOverrideM,
    this.mapAnchor,
    this.depthEdited = false,
    this.chartedDepth,
  });

  final double rodeM;
  final double depthM;
  final AnchorMethod method;

  /// Bow direction used when no compass is available.
  final double manualBowDeg;

  /// User-chosen radius; null = use the suggested one.
  final double? radiusOverrideM;

  /// Anchor placed on the map (method [AnchorMethod.map]).
  final LatLng? mapAnchor;

  /// The user changed the depth in this panel session: charted depth
  /// lookups must not overwrite it.
  final bool depthEdited;

  /// Charted depth at the anchor position (approximate; shown as a hint).
  final DepthSample? chartedDepth;

  DropAnchorForm copyWith({
    double? rodeM,
    double? depthM,
    AnchorMethod? method,
    double? manualBowDeg,
    double? radiusOverrideM,
    bool clearRadiusOverride = false,
    LatLng? mapAnchor,
    bool? depthEdited,
    DepthSample? chartedDepth,
    bool clearChartedDepth = false,
  }) =>
      DropAnchorForm(
        rodeM: rodeM ?? this.rodeM,
        depthM: depthM ?? this.depthM,
        method: method ?? this.method,
        manualBowDeg: manualBowDeg ?? this.manualBowDeg,
        radiusOverrideM:
            clearRadiusOverride ? null : radiusOverrideM ?? this.radiusOverrideM,
        mapAnchor: mapAnchor ?? this.mapAnchor,
        depthEdited: depthEdited ?? this.depthEdited,
        chartedDepth: clearChartedDepth ? null : chartedDepth ?? this.chartedDepth,
      );

  /// Depth typed or stepped by the user.
  DropAnchorForm withUserDepth(double depthM) =>
      copyWith(depthM: depthM, depthEdited: true);

  /// Applies a charted depth lookup: always kept as a hint; also used as the
  /// depth unless the user edited it (or it is implausibly shallow, which
  /// happens in grid cells on the coastline).
  DropAnchorForm withChartedDepth(DepthSample? sample) {
    if (sample == null) return copyWith(clearChartedDepth: true);
    final prefill = !depthEdited && sample.depthM >= minPrefillDepthM;
    return copyWith(
      chartedDepth: sample,
      depthM: prefill ? (sample.depthM * 10).roundToDouble() / 10 : null,
    );
  }

  double suggestedRadius(BoatSettings boat) => suggestedRadiusM(
        rodeM: rodeM,
        depthM: depthM,
        boatLengthM: boat.lengthM,
        gpsMarginM: boat.gpsMarginM,
      ).clamp(minRadiusM, maxRadiusM);

  double radius(BoatSettings boat) =>
      (radiusOverrideM ?? suggestedRadius(boat)).clamp(minRadiusM, maxRadiusM);

  /// The anchor position, or null when the boat position (or the map point)
  /// needed for the chosen method is not known yet.
  LatLng? anchor({
    required LatLng? boat,
    required double? compassDeg,
    required BoatSettings settings,
  }) =>
      switch (method) {
        AnchorMethod.here => boat,
        AnchorMethod.map => mapAnchor ?? boat,
        AnchorMethod.settled => boat == null
            ? null
            : anchorFromSettledPosition(
                boat: boat,
                bowBearingDeg: compassDeg ?? manualBowDeg,
                rodeM: rodeM,
                depthM: depthM,
                gpsToBowM: settings.gpsToBowM,
              ),
      };
}
