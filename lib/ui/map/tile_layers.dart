import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// [activeTileLayers] of the current settings; only changes when a layer
/// setting changes (records compare by value).
final _activeLayersProvider = Provider<List<TileLayerSpec>>((ref) {
  ref.watch(settingsProvider.select((s) => (s.baseMap, s.depthLayer, s.seamarks)));
  return activeTileLayers(ref.read(settingsProvider));
});

/// Base map, depth overlay and seamarks overlay as selected in the settings, with attribution.
///
/// A separate const widget so the map's frequent rebuilds (one per GPS fix)
/// don't recreate tile layers and their providers.
class MapTileLayers extends ConsumerWidget {
  const MapTileLayers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = ref.watch(_activeLayersProvider);
    final night = AnchorColors.of(context).night;
    final factory = ref.watch(tileProviderFactoryProvider);

    if (specs.isEmpty) return const SizedBox.shrink();
    final stack = Stack(children: [for (final s in specs) _layer(s, factory)]);
    return night ? ColorFiltered(colorFilter: nightTileFilter, child: stack) : stack;
  }

  Widget _layer(TileLayerSpec spec, TileProvider Function(TileLayerSpec) factory) {
    final wms = spec.wms;
    final layer = TileLayer(
      key: ValueKey(spec.key),
      urlTemplate: wms == null ? spec.urlTemplate : null,
      wmsOptions: wms == null
          ? null
          : WMSTileLayerOptions(
              baseUrl: wms.baseUrl,
              layers: wms.layers,
              styles: wms.styles,
              format: wms.format,
              version: wms.version,
            ),
      maxNativeZoom: spec.maxNativeZoom,
      maxZoom: 21,
      userAgentPackageName: _userAgentPackage,
      tileProvider: factory(spec),
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
    );
    // Depth overlays are semi-transparent so the base map shows through.
    return wms == null
        ? layer
        : Opacity(key: ValueKey('${spec.key}_o'), opacity: depthOverlayOpacity, child: layer);
  }
}

/// Opacity of the coloured depth overlays (EMODnet / GEBCO WMS).
const depthOverlayOpacity = 0.55;

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
    final layers = ref.watch(_activeLayersProvider);
    // Several layers can share a source (EMODnet base + overlay).
    final specs = {for (final s in layers) s.attribution: s}.values.toList();
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
