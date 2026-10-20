import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/providers.dart';

const baseMapLabels = {
  BaseMap.osm: 'Chart',
  BaseMap.satellite: 'Satellite',
  BaseMap.bathymetry: 'Depth relief',
  BaseMap.none: 'None',
};

const depthLayerLabels = {
  DepthLayer.none: 'None',
  DepthLayer.emodnet: 'EMODnet',
  DepthLayer.gebco: 'GEBCO',
};

/// Base map, depth overlay and seamarks choices, written to [settingsProvider].
/// Used by the map's Layers sheet and in Settings → Map.
class MapLayerOptions extends ConsumerWidget {
  const MapLayerOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void update(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).update(f);
    final theme = Theme.of(context);

    Widget section(IconData icon, String title, String? note, Widget child) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note != null) Text(note, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );

    Widget chips<T>(Map<T, String> labels, T value, ValueChanged<T> onSelected) => Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in labels.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: e.key == value,
                onSelected: (_) => onSelected(e.key),
              ),
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        section(
          Icons.map_outlined,
          'Base map',
          s.baseMap == BaseMap.bathymetry
              ? 'Sea-floor and land relief (EMODnet), best in European waters'
              : null,
          chips(baseMapLabels, s.baseMap, (v) => update((x) => x.copyWith(baseMap: v))),
        ),
        section(
          Icons.water,
          'Depth overlay',
          switch (s.depthLayer) {
            DepthLayer.none => null,
            DepthLayer.emodnet => 'Coloured depth, European seas (~115 m grid)',
            DepthLayer.gebco => 'Coloured depth, worldwide (~460 m grid)',
          },
          chips(depthLayerLabels, s.depthLayer,
              (v) => update((x) => x.copyWith(depthLayer: v))),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.layers_outlined),
          title: const Text('Seamarks (OpenSeaMap)'),
          value: s.seamarks,
          onChanged: (v) => update((x) => x.copyWith(seamarks: v)),
        ),
      ],
    );
  }
}

/// The map's "Layers" bottom sheet.
Future<void> showLayerPicker(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('Map layers', style: Theme.of(context).textTheme.titleLarge),
              ),
              const MapLayerOptions(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Charted depths are approximate. Always check your sounder.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
