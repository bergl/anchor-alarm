import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../../services/location/simulated_location_source.dart';
import '../theme/app_theme.dart';
import '../ui_providers.dart';
import 'assistant_layers.dart';
import 'map_markers.dart';
import 'tile_layers.dart';

/// Whether the map follows the boat. Owned by the screen so it can show a
/// "recenter" button; the map turns following off when the user pans.
class MapFollow extends ChangeNotifier {
  bool _following = true;
  int _recenterRequests = 0;

  bool get following => _following;

  void stopFollowing() {
    if (!_following) return;
    _following = false;
    notifyListeners();
  }

  void recenter() {
    _following = true;
    _recenterRequests++;
    notifyListeners();
  }
}

/// What the map draws, derived from the watch state.
class _MapModel {
  _MapModel(WatchViewState s, AlarmProfile profile, double? compass) {
    final session = s.session;
    final snap = s.snapshot;
    watching = session != null;
    if (session != null) {
      anchor = session.anchor;
      radiusM = snap?.radiusM ?? session.radiusM;
      warningRadiusM = snap?.warningRadiusM ?? session.warningRadiusM;
      state = snap?.state ?? WatchState.safe;
    } else if (s.draft != null) {
      anchor = s.draft!.anchor;
      radiusM = s.draft!.radiusM;
      warningRadiusM = radiusM! * profile.warningRatio;
    }
    boat = (watching ? snap?.position : null) ?? s.fix?.position;
    accuracyM = (watching ? snap?.accuracyM : null) ?? s.fix?.accuracyM;
    final fix = s.fix;
    heading = compass ??
        ((fix?.speedMps ?? 0) > 0.5 ? fix?.courseDeg : null);
  }

  late final bool watching;
  LatLng? anchor;
  double? radiusM;
  double? warningRadiusM;
  WatchState? state;
  LatLng? boat;
  double? accuracyM;
  double? heading;
}

/// Full-screen chart with anchor, rings, boat, track and the anchor→boat line.
class AnchorMap extends ConsumerStatefulWidget {
  const AnchorMap({
    super.key,
    required this.follow,
    required this.onLongPress,
    required this.onAnchorDragged,
  });

  final MapFollow follow;

  /// Long-press on the map at [point].
  final void Function(LatLng point) onLongPress;

  /// The user finished dragging the anchor marker to [point].
  final void Function(LatLng point) onAnchorDragged;

  @override
  ConsumerState<AnchorMap> createState() => _AnchorMapState();
}

class _AnchorMapState extends ConsumerState<AnchorMap> {
  final _map = MapController();
  bool _ready = false;
  int _handledRecenter = 0;

  /// Anchor position while the user drags it (not yet committed).
  LatLng? _dragPos;

  @override
  void initState() {
    super.initState();
    widget.follow.addListener(_onFollowChanged);
  }

  @override
  void dispose() {
    widget.follow.removeListener(_onFollowChanged);
    _map.dispose();
    super.dispose();
  }

  void _onFollowChanged() {
    final f = widget.follow;
    if (f._recenterRequests != _handledRecenter) {
      _handledRecenter = f._recenterRequests;
      _centerOnBoat(animateZoom: true);
    }
  }

  void _centerOnBoat({bool animateZoom = false}) {
    if (!_ready) return;
    final m = _model();
    if (_fitRing(m)) return;
    final target = m.boat ?? m.anchor;
    if (target == null) return;
    final zoom = _map.camera.zoom < 14 && animateZoom ? 17.0 : _map.camera.zoom;
    _map.move(target, zoom);
  }

  /// While watching or placing the anchor, frame the whole alarm ring (and the
  /// boat if it is outside) above the bottom panel. Returns false when there
  /// is no ring to frame.
  bool _fitRing(_MapModel m) {
    final anchor = m.anchor;
    final radius = m.radiusM;
    if (anchor == null || radius == null) return false;
    final pts = [
      for (final b in const [0.0, 90.0, 180.0, 270.0])
        destination(anchor, b, radius * 1.1),
      ?m.boat,
    ];
    final h = MediaQuery.sizeOf(context).height;
    // The drop-anchor panel covers more of the screen than the status card.
    final bottom = m.watching ? 300.0 : h * 0.64;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: EdgeInsets.fromLTRB(24, 120, 24, bottom),
      maxZoom: 19,
    ));
    return true;
  }

  _MapModel _model() => _MapModel(
        ref.read(watchControllerProvider),
        ref.read(activeProfileProvider),
        ref.read(headingProvider).value,
      );

  LatLng _initialCenter() {
    final m = _model();
    return m.boat ?? m.anchor ?? SimulatedLocationSource.defaultAnchor;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(watchControllerProvider);
    final profile = ref.watch(activeProfileProvider);
    final compass = ref.watch(headingProvider).value;
    final track = ref.watch(recentTrackProvider);
    final colors = AnchorColors.of(context);
    final m = _MapModel(s, profile, compass);

    // Follow the boat.
    ref.listen<LatLng?>(
      watchControllerProvider.select(
          (v) => (v.watching ? v.snapshot?.position : null) ?? v.fix?.position),
      (prev, next) {
        if (next != null && widget.follow.following && _ready) {
          if (!_fitRing(_model())) _map.move(next, _map.camera.zoom);
        }
      },
    );
    // Re-frame when the anchor, radius or watch state changes.
    ref.listen<(LatLng?, double?, bool)>(
      watchControllerProvider.select((v) => (
            v.session?.anchor ?? v.draft?.anchor,
            v.snapshot?.radiusM ?? v.session?.radiusM ?? v.draft?.radiusM,
            v.watching,
          )),
      (prev, next) {
        if (widget.follow.following && _ready) _centerOnBoat();
      },
    );

    final anchor = _dragPos ?? m.anchor;
    final ringColor = m.watching ? colors.forState(m.state) : colors.neutral;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _initialCenter(),
        initialZoom: 17,
        minZoom: 3,
        maxZoom: 21,
        backgroundColor: colors.mapBackground,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _ready = true;
          ref.read(mapViewProvider).camera = _map.camera;
          if (widget.follow.following) _centerOnBoat();
        },
        onPositionChanged: (camera, hasGesture) {
          ref.read(mapViewProvider).camera = camera;
          if (hasGesture) widget.follow.stopFollowing();
        },
        onLongPress: (_, point) => widget.onLongPress(point),
      ),
      children: [
        const MapTileLayers(),
        // Swing preview, exposure rose, nearby anchorages (under the rings).
        const AnchorageAssistantLayers(),
        if (track.length > 1)
          PolylineLayer(polylines: [
            Polyline(
              points: track,
              strokeWidth: 3,
              color: colors.track.withValues(alpha: 0.7),
            ),
          ]),
        CircleLayer(circles: [
          if (m.boat != null && m.accuracyM != null)
            CircleMarker(
              point: m.boat!,
              radius: m.accuracyM!,
              useRadiusInMeter: true,
              color: colors.boat.withValues(alpha: 0.10),
              borderColor: colors.boat.withValues(alpha: 0.25),
              borderStrokeWidth: 1,
            ),
          if (anchor != null && m.radiusM != null) ...[
            CircleMarker(
              point: anchor,
              radius: m.radiusM!,
              useRadiusInMeter: true,
              color: ringColor.withValues(alpha: 0.10),
              borderColor: ringColor,
              borderStrokeWidth: 3,
            ),
            CircleMarker(
              point: anchor,
              radius: m.warningRadiusM!,
              useRadiusInMeter: true,
              color: Colors.transparent,
              borderColor: ringColor.withValues(alpha: 0.6),
              borderStrokeWidth: 1.5,
            ),
          ],
        ]),
        if (anchor != null && m.boat != null)
          PolylineLayer(polylines: [
            Polyline(
              points: [anchor, m.boat!],
              strokeWidth: 2,
              color: ringColor.withValues(alpha: 0.9),
              pattern: StrokePattern.dashed(segments: const [8, 6]),
            ),
          ]),
        MarkerLayer(markers: [
          if (m.boat != null)
            Marker(
              point: m.boat!,
              width: BoatMarkerIcon.size,
              height: BoatMarkerIcon.size,
              child: BoatMarkerIcon(headingDeg: m.heading),
            ),
          if (anchor != null)
            Marker(
              point: anchor,
              width: AnchorMarkerIcon.size,
              height: AnchorMarkerIcon.size,
              child: _DraggableAnchor(
                dragging: _dragPos != null,
                draft: !m.watching,
                onStart: () => setState(() => _dragPos = anchor),
                onDelta: (delta) {
                  final cam = _map.camera;
                  final from = _dragPos ?? anchor;
                  setState(() => _dragPos = cam.screenOffsetToLatLng(
                      cam.latLngToScreenOffset(from) + delta));
                },
                onEnd: () {
                  final p = _dragPos;
                  setState(() => _dragPos = null);
                  if (p != null) widget.onAnchorDragged(p);
                },
              ),
            ),
        ]),
        const MapAttribution(),
      ],
    );
  }
}

/// Anchor marker that can be dragged. The pan recognizer wins the gesture
/// arena over the map's pan/zoom recognizer when the drag starts on the marker.
class _DraggableAnchor extends StatelessWidget {
  const _DraggableAnchor({
    required this.dragging,
    required this.draft,
    required this.onStart,
    required this.onDelta,
    required this.onEnd,
  });

  final bool dragging;
  final bool draft;
  final VoidCallback onStart;
  final void Function(Offset delta) onDelta;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onStart(),
          onPanUpdate: (d) => onDelta(d.delta),
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: AnchorMarkerIcon(dragging: dragging, draft: draft),
        ),
      );
}
