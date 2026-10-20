import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/ui/screens/drop_anchor/drop_anchor_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const boat = LatLng(43.1633, 16.3972);
  const settings = BoatSettings(lengthM: 12, gpsToBowM: 6, gpsMarginM: 5);

  test('settled method puts the anchor ahead of the bow', () {
    const form = DropAnchorForm(rodeM: 30, depthM: 5);
    final a = form.anchor(boat: boat, compassDeg: 90, settings: settings)!;
    expect(distanceM(boat, a), closeTo(horizontalRodeM(rodeM: 30, depthM: 5) + 6, 0.1));
    expect(bearingDeg(boat, a), closeTo(90, 0.5));
  });

  test('settled method uses the manual bow direction without compass', () {
    const form = DropAnchorForm(rodeM: 30, depthM: 5, manualBowDeg: 180);
    final a = form.anchor(boat: boat, compassDeg: null, settings: settings)!;
    expect(bearingDeg(boat, a), closeTo(180, 0.5));
  });

  test('here and map methods', () {
    const p = LatLng(43.164, 16.398);
    expect(
      const DropAnchorForm(rodeM: 30, depthM: 5, method: AnchorMethod.here)
          .anchor(boat: boat, compassDeg: 10, settings: settings),
      boat,
    );
    expect(
      const DropAnchorForm(rodeM: 30, depthM: 5, method: AnchorMethod.map, mapAnchor: p)
          .anchor(boat: boat, compassDeg: 10, settings: settings),
      p,
    );
    expect(
      const DropAnchorForm(rodeM: 30, depthM: 5)
          .anchor(boat: null, compassDeg: 10, settings: settings),
      isNull,
    );
  });

  test('radius is suggested unless overridden, clamped to 10–300 m', () {
    const form = DropAnchorForm(rodeM: 30, depthM: 5);
    expect(form.radius(settings), closeTo(46.6, 0.1));
    expect(form.copyWith(radiusOverrideM: 500).radius(settings), maxRadiusM);
    expect(
      form.copyWith(radiusOverrideM: 80).copyWith(clearRadiusOverride: true).radius(settings),
      closeTo(46.6, 0.1),
    );
  });
}
