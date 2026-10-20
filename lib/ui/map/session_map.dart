import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';
import 'map_markers.dart';
import 'tile_layers.dart';

/// Static map of a finished session: anchor, rings and the recorded track.
class SessionMap extends StatelessWidget {
  const SessionMap({super.key, required this.session, required this.track});

  final AnchorSession session;
  final List<TrackPoint> track;

  LatLngBounds _bounds() {
    final a = session.anchor;
    final r = session.radiusM * 1.1;
    return LatLngBounds.fromPoints([
      destination(a, 0, r),
      destination(a, 90, r),
      destination(a, 180, r),
      destination(a, 270, r),
      for (final p in track) p.position,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = AnchorColors.of(context);
    final hadAlarm = session.alerts.any((e) => e.reason.isAlarm);
    final ring = hadAlarm ? c.alarm : c.safe;
    final pts = [for (final p in track) p.position];
    return FlutterMap(
      // The track loads after the session; rebuild so the initial fit includes it.
      key: ValueKey(track.length),
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: _bounds(),
          padding: const EdgeInsets.all(24),
          maxZoom: 19,
        ),
        backgroundColor: c.mapBackground,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        const MapTileLayers(),
        CircleLayer(circles: [
          CircleMarker(
            point: session.anchor,
            radius: session.radiusM,
            useRadiusInMeter: true,
            color: ring.withValues(alpha: 0.08),
            borderColor: ring,
            borderStrokeWidth: 2.5,
          ),
          CircleMarker(
            point: session.anchor,
            radius: session.warningRadiusM,
            useRadiusInMeter: true,
            color: Colors.transparent,
            borderColor: ring.withValues(alpha: 0.6),
            borderStrokeWidth: 1.5,
          ),
        ]),
        if (pts.length > 1)
          PolylineLayer(polylines: [
            Polyline(points: pts, strokeWidth: 2.5, color: c.track),
          ]),
        MarkerLayer(markers: [
          Marker(
            point: session.anchor,
            width: AnchorMarkerIcon.size,
            height: AnchorMarkerIcon.size,
            child: const AnchorMarkerIcon(),
          ),
        ]),
        const MapAttribution(),
      ],
    );
  }
}
