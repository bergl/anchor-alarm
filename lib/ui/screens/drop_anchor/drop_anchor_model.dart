import 'package:latlong2/latlong.dart';

import '../../../domain/geo.dart';
import '../../../domain/models.dart';

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

/// Inputs of the "Drop anchor" form, all in metres / degrees.
class DropAnchorForm {
  const DropAnchorForm({
    required this.rodeM,
    required this.depthM,
    this.method = AnchorMethod.settled,
    this.manualBowDeg = 0,
    this.radiusOverrideM,
    this.mapAnchor,
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

  DropAnchorForm copyWith({
    double? rodeM,
    double? depthM,
    AnchorMethod? method,
    double? manualBowDeg,
    double? radiusOverrideM,
    bool clearRadiusOverride = false,
    LatLng? mapAnchor,
  }) =>
      DropAnchorForm(
        rodeM: rodeM ?? this.rodeM,
        depthM: depthM ?? this.depthM,
        method: method ?? this.method,
        manualBowDeg: manualBowDeg ?? this.manualBowDeg,
        radiusOverrideM:
            clearRadiusOverride ? null : radiusOverrideM ?? this.radiusOverrideM,
        mapAnchor: mapAnchor ?? this.mapAnchor,
      );

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
