import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/remote_controllers.dart';
import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../../services/remote/firebase_config.dart';
import '../../services/remote/remote_models.dart';
import '../map/map_markers.dart';
import '../map/tile_layers.dart';
import '../theme/app_theme.dart';
import '../widgets/state_banner.dart';

/// "Monitor a boat": join with a link or code, and the list of monitored boats.
class MonitorBoatsScreen extends ConsumerStatefulWidget {
  const MonitorBoatsScreen({super.key, this.initialInput});

  /// Link or code to join right away (web `#join=` links).
  final String? initialInput;

  @override
  ConsumerState<MonitorBoatsScreen> createState() => _MonitorBoatsScreenState();
}

class _MonitorBoatsScreenState extends ConsumerState<MonitorBoatsScreen> {
  late final _input = TextEditingController(text: widget.initialInput ?? '');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.initialInput ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _join();
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) setState(() => _input.text = text.trim());
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ref.read(monitoredBoatsProvider.notifier).join(_input.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.ok ? null : res.message;
    });
    if (res.ok) {
      _input.clear();
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MonitorScreen(watchId: res.watchId!),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(remoteServicesProvider) != null;
    final boats = ref.watch(monitoredBoatsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Monitor a boat')),
      body: !configured
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(remoteNotConfiguredMessage),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Paste the link or code shared from the boat\'s Anchor Alarm '
                  '(Watch controls → Share this watch). This device then shows the '
                  'boat live and sounds its alarm when the boat\'s alarm goes off.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _input,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Link or code',
                    hintText: 'https://…#join=…',
                    errorText: _error,
                    errorMaxLines: 3,
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste),
                      onPressed: _paste,
                    ),
                  ),
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.visibility),
                  label: const Text('Start monitoring'),
                  onPressed: _busy ? null : _join,
                ),
                const SizedBox(height: 24),
                if (boats.isNotEmpty) Text('Monitored boats', style: theme.textTheme.titleMedium),
                for (final b in boats) _MonitoredBoatTile(boat: b),
              ],
            ),
    );
  }
}

class _MonitoredBoatTile extends ConsumerWidget {
  const _MonitoredBoatTile({required this.boat});
  final MonitoredBoat boat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(monitorControllerProvider(boat.watchId));
    final c = AnchorColors.of(context);
    final w = m.watch;
    final (color, text) = _statusLine(m, c);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.sailing, color: w == null ? c.neutral : c.forState(w.state)),
      title: Text(w?.displayName ?? boat.name ?? 'Boat'),
      subtitle: Text(text, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MonitorScreen(watchId: boat.watchId),
      )),
    );
  }
}

(Color?, String) _statusLine(MonitorViewState m, AnchorColors c) {
  final w = m.watch;
  switch (m.problem) {
    case MonitorProblem.accessDenied:
      return (c.alarm, 'No access — the boat stopped sharing');
    case MonitorProblem.offline:
      return (c.warning, 'No connection');
    case MonitorProblem.other:
      return (c.warning, 'Unavailable');
    case null:
  }
  if (w == null) return (null, 'Connecting…');
  return switch (m.freshness!) {
    Freshness.ended => (c.neutral, 'Watch ended'),
    Freshness.lost => (
        c.alarm,
        'Lost contact — last update ${w.updatedAt == null ? '?' : clockTime(w.updatedAt!)}'
      ),
    Freshness.stale => (c.warning, '${stateLabel(w.state)} · ${updatedAgo(w.updatedAt, m.now)}'),
    Freshness.fresh => (null, '${stateLabel(w.state)} · ${updatedAgo(w.updatedAt, m.now)}'),
  };
}

/// Live view of a monitored boat.
class MonitorScreen extends ConsumerWidget {
  const MonitorScreen({super.key, required this.watchId});
  final String watchId;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop monitoring this boat?'),
        content: const Text('This device will no longer show the boat or get its alarms.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop monitoring')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(monitoredBoatsProvider.notifier).leave(watchId);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(monitorControllerProvider(watchId));
    final unit = ref.watch(settingsProvider.select((s) => s.distanceUnit));
    final boat = ref.watch(monitoredBoatsProvider).where((b) => b.watchId == watchId).firstOrNull;
    final c = AnchorColors.of(context);
    final theme = Theme.of(context);
    final w = m.watch;
    final (statusColor, statusText) = _statusLine(m, c);

    return Scaffold(
      appBar: AppBar(
        title: Text(w?.displayName ?? boat?.name ?? 'Boat'),
        actions: [
          IconButton(
            tooltip: 'Stop monitoring',
            icon: const Icon(Icons.logout),
            onPressed: () => _leave(context, ref),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (w != null) Positioned.fill(child: RemoteWatchMap(watch: w)),
          if (w == null)
            Center(
              child: m.problem == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(statusText, textAlign: TextAlign.center),
                    ),
            ),
          if (w != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (m.freshness == Freshness.ended)
                            _InfoBanner(
                              color: c.neutral,
                              icon: Icons.anchor,
                              title: 'WATCH ENDED',
                              text: w.endedAt == null ? '' : 'Ended at ${clockTime(w.endedAt!)}',
                            )
                          else if (m.freshness == Freshness.lost)
                            _InfoBanner(
                              color: c.alarm,
                              icon: Icons.signal_wifi_connected_no_internet_4,
                              title: 'LOST CONTACT',
                              text: 'No update from the boat since '
                                  '${w.updatedAt == null ? '?' : clockTime(w.updatedAt!)}. '
                                  'Last known state: ${stateLabel(w.state).toLowerCase()}.',
                            )
                          else
                            StateBanner(state: w.state, reasons: w.reasons),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  w.distanceM == null
                                      ? 'No position'
                                      : '${formatDistance(w.distanceM, unit)} from anchor',
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              Text('alarm at ${formatDistance(w.radiusM, unit)}',
                                  style: theme.textTheme.bodyMedium),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.update, size: 18, color: statusColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  m.freshness == Freshness.ended
                                      ? 'Watch ended'
                                      : updatedAgo(w.updatedAt, m.now),
                                  key: const Key('monitor-updated'),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: statusColor == null ? null : FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (m.silencedHere)
                                const Text('Silenced here'),
                            ],
                          ),
                          if (m.problem == MonitorProblem.accessDenied)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'The boat stopped sharing; this view is no longer updated.',
                                style: TextStyle(color: c.alarm),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.color, required this.icon, required this.title, required this.text});
  final Color color;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AnchorColors.of(context);
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: c.onState),
        child: Row(children: [
          Icon(icon, color: c.onState, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                if (text.isNotEmpty) Text(text, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Map of a monitored watch: anchor, warning and alarm rings, boat position.
class RemoteWatchMap extends StatefulWidget {
  const RemoteWatchMap({super.key, required this.watch});
  final RemoteWatch watch;

  @override
  State<RemoteWatchMap> createState() => _RemoteWatchMapState();
}

class _RemoteWatchMapState extends State<RemoteWatchMap> {
  final _map = MapController();
  bool _ready = false;
  bool _userMoved = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  CameraFit _fit() {
    final w = widget.watch;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([
        for (final b in const [0.0, 90.0, 180.0, 270.0]) destination(w.anchor, b, w.radiusM * 1.15),
        ?w.boat,
      ]),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 240),
      maxZoom: 19,
    );
  }

  @override
  void didUpdateWidget(RemoteWatchMap old) {
    super.didUpdateWidget(old);
    final moved = old.watch.boat != widget.watch.boat ||
        old.watch.anchor != widget.watch.anchor ||
        old.watch.radiusM != widget.watch.radiusM;
    if (_ready && !_userMoved && moved) _map.fitCamera(_fit());
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.watch;
    final c = AnchorColors.of(context);
    final ring = w.ended ? c.neutral : c.forState(w.state);
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCameraFit: _fit(),
        backgroundColor: c.mapBackground,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () => _ready = true,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) _userMoved = true;
        },
      ),
      children: [
        const MapTileLayers(),
        CircleLayer(circles: [
          if (w.boat != null && w.accuracyM != null)
            CircleMarker(
              point: w.boat!,
              radius: w.accuracyM!,
              useRadiusInMeter: true,
              color: c.boat.withValues(alpha: 0.10),
              borderColor: c.boat.withValues(alpha: 0.25),
              borderStrokeWidth: 1,
            ),
          CircleMarker(
            point: w.anchor,
            radius: w.radiusM,
            useRadiusInMeter: true,
            color: ring.withValues(alpha: 0.10),
            borderColor: ring,
            borderStrokeWidth: 3,
          ),
          CircleMarker(
            point: w.anchor,
            radius: w.warningRadiusM,
            useRadiusInMeter: true,
            color: Colors.transparent,
            borderColor: ring.withValues(alpha: 0.6),
            borderStrokeWidth: 1.5,
          ),
        ]),
        if (w.boat != null)
          PolylineLayer(polylines: [
            Polyline(
              points: <LatLng>[w.anchor, w.boat!],
              strokeWidth: 2,
              color: ring.withValues(alpha: 0.9),
              pattern: StrokePattern.dashed(segments: const [8, 6]),
            ),
          ]),
        MarkerLayer(markers: [
          if (w.boat != null)
            Marker(
              point: w.boat!,
              width: BoatMarkerIcon.size,
              height: BoatMarkerIcon.size,
              child: const BoatMarkerIcon(),
            ),
          Marker(
            point: w.anchor,
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

/// Full-screen alarm for a monitored boat. "Silence (here)" silences only
/// this device; the boat keeps ringing until someone silences it on board.
class RemoteAlarmOverlay extends ConsumerWidget {
  const RemoteAlarmOverlay({super.key, required this.watchId, this.onOpen});
  final String watchId;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(monitorControllerProvider(watchId));
    final unit = ref.watch(settingsProvider.select((s) => s.distanceUnit));
    final c = AnchorColors.of(context);
    final fg = c.night ? Colors.black : Colors.white;
    final w = m.watch;
    final alarms = (w?.alarmReasons ?? const <AlertReason>{}).toList();
    final main = alarms.isEmpty ? AlertReason.drag : alarms.first;
    return Material(
      color: c.alarm,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.notifications_active, size: 72, color: fg),
              Text(w?.displayName ?? 'Boat',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(alertTitle(main),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontSize: 34, fontWeight: FontWeight.w900)),
              if (w?.distanceM != null) ...[
                const SizedBox(height: 12),
                Text(formatDistance(w!.distanceM, unit),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontSize: 56, fontWeight: FontWeight.w800)),
                Text('from anchor · alarm at ${formatDistance(w.radiusM, unit)}',
                    textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 18)),
              ],
              const Spacer(),
              SizedBox(
                height: 110,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: fg,
                    foregroundColor: c.alarm,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: () => ref.read(monitorControllerProvider(watchId).notifier).silenceHere(),
                  child: const Text('SILENCE (HERE)',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 8),
              Text('Silences this device only. The alarm on the boat keeps sounding.',
                  textAlign: TextAlign.center, style: TextStyle(color: fg)),
              if (onOpen != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: fg,
                    side: BorderSide(color: fg),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: onOpen,
                  child: const Text('Show the boat'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
