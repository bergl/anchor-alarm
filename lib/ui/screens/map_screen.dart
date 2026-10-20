import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../map/anchor_map.dart';
import '../ui_providers.dart';
import '../widgets/alarm_overlay.dart';
import '../widgets/app_menu.dart';
import '../widgets/map_layer_options.dart';
import '../widgets/offline_chart_chip.dart';
import '../widgets/permission_notice.dart';
import '../widgets/simulator_panel.dart';
import '../widgets/status_hud.dart';
import '../widgets/watch_controls_sheet.dart';
import '../widgets/web_banner.dart';
import 'drop_anchor/drop_anchor_model.dart';
import 'drop_anchor/drop_anchor_panel.dart';
import 'drop_anchor/drop_anchor_providers.dart';

/// Main screen: the chart with the anchor watch status on top.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.restoreOnStart = true});

  /// Restore a watch that was active when the app was closed.
  final bool restoreOnStart;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _follow = MapFollow();
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _follow.addListener(_rebuild);
    if (widget.restoreOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(watchControllerProvider.notifier).restore();
      });
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _follow.removeListener(_rebuild);
    _follow.dispose();
    super.dispose();
  }

  WatchController get _controller => ref.read(watchControllerProvider.notifier);

  void _openDropAnchor({LatLng? at}) {
    final s = ref.read(watchControllerProvider);
    if (s.permission == null) _controller.requestPermission();
    ref.read(dropAnchorFormProvider.notifier).reset(
          method: at == null ? AnchorMethod.settled : AnchorMethod.map,
          mapAnchor: at,
        );
    ref.read(mapPanelProvider.notifier).show(MapPanel.dropAnchor);
  }

  void _closePanel() => ref.read(mapPanelProvider.notifier).show(MapPanel.status);

  Future<bool> _confirmMoveAnchor() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move anchor here?'),
        content: const Text('The alarm rings will be centred on the new position.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move anchor'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onLongPress(LatLng p) async {
    final watching = ref.read(watchControllerProvider).watching;
    final sim = ref.read(settingsProvider).useSimulator;
    final panel = ref.read(mapPanelProvider);

    var action = _LongPressAction.anchor;
    if (sim) {
      final choice = await showModalBottomSheet<_LongPressAction>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.anchor),
              title: Text(watching ? 'Move anchor here' : 'Place anchor here'),
              onTap: () => Navigator.pop(context, _LongPressAction.anchor),
            ),
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Move simulated boat here'),
              onTap: () => Navigator.pop(context, _LongPressAction.simBoat),
            ),
          ]),
        ),
      );
      if (choice == null) return;
      action = choice;
    }
    if (!mounted) return;

    if (action == _LongPressAction.simBoat) {
      ref.read(simulatorProvider).relocate(p);
      _follow.recenter();
      return;
    }
    if (watching) {
      if (await _confirmMoveAnchor()) _controller.moveAnchor(p);
    } else if (panel == MapPanel.dropAnchor) {
      ref.read(dropAnchorFormProvider.notifier).placeOnMap(p);
    } else {
      _openDropAnchor(at: p);
    }
  }

  Future<void> _onAnchorDragged(LatLng p) async {
    if (ref.read(watchControllerProvider).watching) {
      if (await _confirmMoveAnchor()) _controller.moveAnchor(p);
    } else {
      ref.read(dropAnchorFormProvider.notifier).placeOnMap(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ringing = ref.watch(
        watchControllerProvider.select((s) => s.snapshot?.ringing ?? false));
    final watching = ref.watch(watchControllerProvider.select((s) => s.watching));
    final panel = ref.watch(mapPanelProvider);
    final showDropPanel = panel == MapPanel.dropAnchor && !watching;

    ref.listen<bool>(watchControllerProvider.select((s) => s.resumed), (_, resumed) {
      if (resumed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Anchor watch resumed after the app restarted.'),
        ));
      }
    });

    final media = MediaQuery.of(context);
    return Scaffold(
      key: _scaffold,
      endDrawer: const AppMenuDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnchorMap(
              follow: _follow,
              onLongPress: _onLongPress,
              onAnchorDragged: _onAnchorDragged,
            ),
          ),
          // Top bar: simulator chip, banners, menu and recenter.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [SimulatorChip(), OfflineChartChip()],
                          ),
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        _RoundButton(
                          tooltip: 'Menu',
                          icon: Icons.menu,
                          onPressed: () => _scaffold.currentState?.openEndDrawer(),
                        ),
                        const SizedBox(height: 8),
                        _RoundButton(
                          tooltip: 'Layers',
                          icon: Icons.layers,
                          onPressed: () => showLayerPicker(context),
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const WebWatchBanner(),
                  if (!showDropPanel) const PermissionNotice(),
                  if (!_follow.following)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _RoundButton(
                          tooltip: 'Recenter on boat',
                          icon: Icons.my_location,
                          onPressed: _follow.recenter,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Bottom: status or drop-anchor form.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 640,
                  maxHeight: media.size.height * (showDropPanel ? 0.62 : 0.55),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: showDropPanel
                      ? DropAnchorPanel(onClose: _closePanel)
                      : StatusHud(
                          onDropAnchor: _openDropAnchor,
                          onAdjust: () => showWatchControlsSheet(context),
                          onStop: () => confirmStopWatch(context, ref),
                        ),
                ),
              ),
            ),
          ),
          if (ringing)
            Positioned.fill(
              child: AlarmOverlay(onStopWatch: () => confirmStopWatch(context, ref)),
            ),
        ],
      ),
    );
  }
}

enum _LongPressAction { anchor, simBoat }

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton(
        heroTag: tooltip,
        mini: false,
        tooltip: tooltip,
        onPressed: onPressed,
        child: Icon(icon, size: 28),
      );
}
