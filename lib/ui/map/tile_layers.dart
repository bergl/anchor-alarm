import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/providers.dart';
import '../../services/map/tile_cache.dart';
import '../theme/app_theme.dart';

const _userAgentPackage = 'app.anchoralarm.anchor_alarm';

/// Creates the [TileProvider] for a layer: the persistent [CachingTileProvider]
/// (disk cache on mobile, browser cache on web). Each [TileLayer] disposes its
/// provider, so this returns a new instance per call. Overridden in tests.
final tileProviderFactoryProvider =
    Provider<TileProvider Function(TileLayerSpec spec)>((ref) {
  final cache = ref.watch(tileCacheProvider);
  return (spec) => CachingTileProvider(layer: spec, cache: cache);
});

/// Base map + seamarks overlay as selected in the settings, with attribution.
///
/// A separate const widget so the map's frequent rebuilds (one per GPS fix)
/// don't recreate tile layers and their providers.
class MapTileLayers extends ConsumerWidget {
  const MapTileLayers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseMap = ref.watch(settingsProvider.select((s) => s.baseMap));
    final seamarks = ref.watch(settingsProvider.select((s) => s.seamarks));
    final night = AnchorColors.of(context).night;
    final factory = ref.watch(tileProviderFactoryProvider);

    final base = switch (baseMap) {
      BaseMap.osm => TileLayerSpec.osm,
      BaseMap.satellite => TileLayerSpec.esriSatellite,
      BaseMap.none => null,
    };
    final layers = <Widget>[
      if (base != null) _layer(base, factory),
      if (seamarks) _layer(TileLayerSpec.openSeaMap, factory),
    ];
    if (layers.isEmpty) return const SizedBox.shrink();
    final stack = Stack(children: layers);
    return night ? ColorFiltered(colorFilter: nightTileFilter, child: stack) : stack;
  }

  Widget _layer(TileLayerSpec spec, TileProvider Function(TileLayerSpec) factory) =>
      TileLayer(
        key: ValueKey(spec.key),
        urlTemplate: spec.urlTemplate,
        maxNativeZoom: spec.maxNativeZoom,
        maxZoom: 21,
        userAgentPackageName: _userAgentPackage,
        tileProvider: factory(spec),
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
      );
}

/// Turns tiles into dim red-on-black for the night theme (inverted luminance
/// into the red channel only).
const nightTileFilter = ColorFilter.matrix(<double>[
  -0.13, -0.43, -0.04, 0, 140, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Attribution for the tile sources currently shown.
class MapAttribution extends ConsumerWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseMap = ref.watch(settingsProvider.select((s) => s.baseMap));
    final seamarks = ref.watch(settingsProvider.select((s) => s.seamarks));
    final specs = [
      if (baseMap == BaseMap.osm) TileLayerSpec.osm,
      if (baseMap == BaseMap.satellite) TileLayerSpec.esriSatellite,
      if (seamarks) TileLayerSpec.openSeaMap,
    ];
    if (specs.isEmpty) return const SizedBox.shrink();
    return RichAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      showFlutterMapAttribution: false,
      attributions: [
        for (final s in specs)
          TextSourceAttribution(
            s.attribution.replaceFirst('© ', ''),
            prependCopyright: s.attribution.startsWith('©'),
          ),
      ],
    );
  }
}
