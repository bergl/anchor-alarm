import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/format.dart';
import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../services/map/tile_layer_spec.dart';
import '../ui_providers.dart';
import '../widgets/number_input.dart';
import '../widgets/offline_download.dart';
import '../widgets/test_alarm.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void update(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).update(f);
    void updateBoat(BoatSettings Function(BoatSettings) f) =>
        update((x) => x.copyWith(boat: f(x.boat)));
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Header('Alarm'),
          ListTile(
            leading: const Icon(Icons.volume_up),
            title: const Text('Test the alarm'),
            subtitle: const Text('Check it is loud enough to wake you'),
            trailing: FilledButton.tonal(
              onPressed: () => runTestAlarm(context, ref),
              child: const Text('Test'),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.light_mode_outlined),
            title: const Text('Keep screen on while watching'),
            subtitle: const Text('Uses more battery — keep the phone on a charger'),
            value: s.keepScreenOn,
            onChanged: (v) => update((x) => x.copyWith(keepScreenOn: v)),
          ),
          if (isAndroid) const _BatteryOptimisationTile(),
          const _Header('Display'),
          _SegmentTile<ThemePref>(
            icon: Icons.contrast,
            title: 'Theme',
            value: s.theme,
            options: const {
              ThemePref.system: 'System',
              ThemePref.day: 'Day',
              ThemePref.night: 'Night (red)',
            },
            onChanged: (v) => update((x) => x.copyWith(theme: v)),
          ),
          _SegmentTile<DistanceUnit>(
            icon: Icons.straighten,
            title: 'Distances',
            value: s.distanceUnit,
            options: const {DistanceUnit.metres: 'Metres', DistanceUnit.feet: 'Feet'},
            onChanged: (v) => update((x) => x.copyWith(distanceUnit: v)),
          ),
          _SegmentTile<DistanceUnit>(
            icon: Icons.water,
            title: 'Depth',
            value: s.depthUnit,
            options: const {DistanceUnit.metres: 'Metres', DistanceUnit.feet: 'Feet'},
            onChanged: (v) => update((x) => x.copyWith(depthUnit: v)),
          ),
          const _Header('Map'),
          _SegmentTile<BaseMap>(
            icon: Icons.map_outlined,
            title: 'Base map',
            value: s.baseMap,
            options: const {
              BaseMap.osm: 'Chart',
              BaseMap.satellite: 'Satellite',
              BaseMap.none: 'None',
            },
            onChanged: (v) => update((x) => x.copyWith(baseMap: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.layers_outlined),
            title: const Text('Seamarks (OpenSeaMap)'),
            value: s.seamarks,
            onChanged: (v) => update((x) => x.copyWith(seamarks: v)),
          ),
          if (offlineDownloadSupported) ...[
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Download map for offline use'),
              subtitle: const Text('The area last shown on the map, a few zoom levels deep'),
              onTap: () => runOfflineDownload(context, ref),
            ),
            const _CacheSizeTile(),
          ],
          const _Header('Boat'),
          _DistanceTile(
            title: 'Boat length',
            valueM: s.boat.lengthM,
            unit: s.distanceUnit,
            onChanged: (m) => updateBoat((b) => b.copyWith(lengthM: m)),
          ),
          _DistanceTile(
            title: 'Phone/GPS to bow',
            subtitle: 'Where the phone usually is, to the bow roller',
            valueM: s.boat.gpsToBowM,
            unit: s.distanceUnit,
            onChanged: (m) => updateBoat((b) => b.copyWith(gpsToBowM: m)),
          ),
          _DistanceTile(
            title: 'GPS margin',
            subtitle: 'Added to the alarm radius',
            valueM: s.boat.gpsMarginM,
            unit: s.distanceUnit,
            onChanged: (m) => updateBoat((b) => b.copyWith(gpsMarginM: m)),
          ),
          const _Header('Demo'),
          SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Use GPS simulator (demo)'),
            subtitle: const Text('A simulated boat instead of the phone\'s GPS'),
            value: s.useSimulator,
            onChanged: (v) => update((x) => x.copyWith(useSimulator: v)),
          ),
          const _Header('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Anchor Alarm'),
            subtitle: const Text('Map data and licences'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Anchor Alarm',
              applicationIcon: const Icon(Icons.anchor, size: 40),
              children: [
                const Text(
                  'An aid to good seamanship — never a substitute for a proper '
                  'anchor watch.\n',
                ),
                for (final spec in TileLayerSpec.all) Text(spec.attribution),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

class _SegmentTile<T extends Object> extends StatelessWidget {
  const _SegmentTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final e in options.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      );
}

class _DistanceTile extends StatelessWidget {
  const _DistanceTile({
    required this.title,
    required this.valueM,
    required this.unit,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final double valueM;
  final DistanceUnit unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Text(
          formatDistance(valueM, unit, decimals: 1),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        onTap: () async {
          final v = await showNumberDialog(
            context,
            title: title,
            initial: fromMetres(valueM, unit),
            suffix: unitSuffix(unit),
            decimals: 1,
            max: 200,
          );
          if (v != null) onChanged(toMetres(v, unit));
        },
      );
}

/// Android: asks to exempt the app from battery optimisation.
class _BatteryOptimisationTile extends ConsumerStatefulWidget {
  const _BatteryOptimisationTile();

  @override
  ConsumerState<_BatteryOptimisationTile> createState() => _BatteryOptimisationTileState();
}

class _BatteryOptimisationTileState extends ConsumerState<_BatteryOptimisationTile>
    with WidgetsBindingObserver {
  bool? _exempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check when returning from the system dialog/settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final v = await ref.read(failsafeProvider).isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _exempt = v);
  }

  @override
  Widget build(BuildContext context) {
    final exempt = _exempt;
    return ListTile(
      leading: Icon(exempt == true ? Icons.battery_full : Icons.battery_alert),
      title: const Text('Battery optimisation'),
      subtitle: Text(exempt == true
          ? 'Off for Anchor Alarm — Android will not stop the watch to save battery.'
          : 'Android may stop the watch to save battery. Allow the app to run '
              'unrestricted.'),
      isThreeLine: true,
      trailing: exempt == true
          ? null
          : FilledButton.tonal(
              onPressed: () async {
                await ref.read(failsafeProvider).requestIgnoreBatteryOptimizations();
                await _check();
              },
              child: const Text('Allow'),
            ),
    );
  }
}

class _CacheSizeTile extends ConsumerWidget {
  const _CacheSizeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(tileCacheSizeProvider);
    return ListTile(
      leading: const Icon(Icons.sd_storage_outlined),
      title: const Text('Offline map cache'),
      subtitle: Text(size.when(
        data: formatBytes,
        loading: () => '…',
        error: (_, _) => 'unknown',
      )),
      trailing: TextButton(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Clear the offline map cache?'),
              content: const Text('Downloaded areas will need internet again.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
              ],
            ),
          );
          if (ok != true) return;
          await ref.read(tileDownloaderProvider).clearCache();
          ref.invalidate(tileCacheSizeProvider);
        },
        child: const Text('Clear'),
      ),
    );
  }
}
