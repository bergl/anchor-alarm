import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/anchorage_assistant.dart';
import '../../app/watch_controller.dart';
import '../../domain/exposure.dart';
import '../../domain/geo.dart';
import '../../domain/swing_preview.dart';
import '../../services/map/anchorage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/anchorage_check.dart';

/// Anchoring assistant overlays, drawn under the alarm rings:
/// * the swing preview — the arc the boat sweeps over the next 12 h as the
///   forecast wind turns (draft anchor, or while the check is open), with
///   small wind arrows at the expected boat positions;
/// * the 16-sector exposure rose around the anchor while the anchorage
///   check is open;
/// * nearby anchorages from OSM when "Show on map" is on.
class AnchorageAssistantLayers extends ConsumerWidget {
  const AnchorageAssistantLayers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swing = ref.watch(swingPreviewProvider);
    final check = ref.watch(anchorageCheckProvider);
    final ring = ref.watch(watchControllerProvider.select((s) => (
          s.session?.anchor ?? s.draft?.anchor,
          s.snapshot?.radiusM ?? s.session?.radiusM ?? s.draft?.radiusM,
        )));
    final colors = AnchorColors.of(context);
    final night = colors.night;
    final (anchor, radius) = ring;

    final polygons = <Polygon>[];
    final markers = <Marker>[];

    // Exposure rose: a band of 16 wedges outside the alarm ring.
    final exp = check.exposure;
    if (check.expanded && exp != null && anchor != null && radius != null &&
        distanceM(exp.anchor, anchor) < 200) {
      final inner = radius * 1.12;
      final outer = radius * 1.4;
      for (final s in exp.sectors) {
        final a0 = s.bearingDeg - sectorWidthDeg / 2 + 1;
        final a1 = s.bearingDeg + sectorWidthDeg / 2 - 1;
        final c = shelterColor(context, s.rating);
        polygons.add(Polygon(
          points: [
            for (var i = 0; i <= 4; i++) destination(anchor, a0 + (a1 - a0) * i / 4, outer),
            for (var i = 4; i >= 0; i--) destination(anchor, a0 + (a1 - a0) * i / 4, inner),
          ],
          color: c.withValues(alpha: s.rating == ShelterRating.exposed ? 0.38 : 0.2),
          borderColor: c.withValues(alpha: 0.5),
          borderStrokeWidth: 1,
        ));
      }
    }

    // Swing preview wedge.
    final SwingPreview? sw = swing;
    if (sw != null) {
      final arcColor = night ? AppTheme.nightRed : const Color(0xFF6A1B9A);
      // At least ±6° so a steady wind still shows where the boat lies.
      final sweep = math.max(sw.sweepDeg, 12.0);
      final start = sw.startDeg - (sweep - sw.sweepDeg) / 2;
      final steps = math.max(4, (sweep / 5).ceil());
      polygons.add(Polygon(
        points: [
          sw.anchor,
          for (var i = 0; i <= steps; i++)
            destination(sw.anchor, start + sweep * i / steps, sw.radiusM),
        ],
        color: arcColor.withValues(alpha: night ? 0.25 : 0.16),
        borderColor: arcColor.withValues(alpha: 0.8),
        borderStrokeWidth: 1.5,
        pattern: StrokePattern.dashed(segments: const [6, 4]),
      ));
      // Wind arrows every 3 h at the boat's expected position.
      for (var i = 0; i < sw.points.length; i += 3) {
        final p = sw.points[i];
        markers.add(Marker(
          point: p.position,
          width: 24,
          height: 24,
          child: _WindArrow(
            downwindDeg: p.boatBearingDeg,
            color: arcColor,
            label: 'Wind ${compass16Name(p.windFromDeg)}'
                '${p.windKn == null ? '' : ' ${p.windKn!.round()} kn'}',
          ),
        ));
      }
    }

    // Nearby anchorages.
    final nearby = check.anchorages;
    if (check.showNearbyOnMap && nearby != null) {
      for (final a in nearby) {
        markers.add(Marker(
          point: a.position,
          width: 30,
          height: 30,
          child: _NearbyMarker(anchorage: a, night: night),
        ));
      }
    }

    if (polygons.isEmpty && markers.isEmpty) return const SizedBox.shrink();
    return Stack(children: [
      if (polygons.isNotEmpty) PolygonLayer(polygons: polygons, simplificationTolerance: 0),
      if (markers.isNotEmpty) MarkerLayer(markers: markers),
    ]);
  }
}

class _WindArrow extends StatelessWidget {
  const _WindArrow({required this.downwindDeg, required this.color, required this.label});
  final double downwindDeg;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: Transform.rotate(
          angle: downwindDeg * math.pi / 180,
          child: Icon(Icons.arrow_upward, size: 20, color: color, shadows: [
            // No white at night.
            Shadow(
              color: AnchorColors.of(context).night ? Colors.black : Colors.white70,
              blurRadius: 3,
            ),
          ]),
        ),
      );
}

class _NearbyMarker extends StatelessWidget {
  const _NearbyMarker({required this.anchorage, required this.night});
  final NearbyAnchorage anchorage;
  final bool night;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = anchorage.kind == AnchorageKind.marina ? Icons.sailing : Icons.anchor;
    return Tooltip(
      message: '${anchorage.label} · ${anchorageKindLabel(anchorage.kind)} · '
          '${(anchorage.distanceM / 1000).toStringAsFixed(1)} km',
      child: Container(
        decoration: BoxDecoration(
          color: night ? Colors.black : scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: night ? AppTheme.nightRed : scheme.primary, width: 1.5),
        ),
        child: Icon(icon, size: 16, color: night ? AppTheme.nightRedBright : scheme.primary),
      ),
    );
  }
}
