import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/providers.dart';
import '../../services/map/tile_cache.dart';
import '../ui_providers.dart';

/// Whether "download this area" is available (not on the web).
bool get offlineDownloadSupported => TileDownloader.supported;

/// Layers to download: the selected base map plus seamarks when shown.
List<TileLayerSpec> offlineLayers(AppSettings s) => [
      if (s.baseMap == BaseMap.osm) TileLayerSpec.osm,
      if (s.baseMap == BaseMap.satellite) TileLayerSpec.esriSatellite,
      if (s.seamarks) TileLayerSpec.openSeaMap,
    ];

/// Downloads the area currently visible on the main map, from the current
/// zoom up to 3 levels deeper (fewer if that would exceed the tile limit).
Future<void> runOfflineDownload(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

  final camera = ref.read(mapViewProvider).camera;
  final layers = offlineLayers(ref.read(settingsProvider));
  if (camera == null) {
    say('Open the map and show the area you want first.');
    return;
  }
  if (layers.isEmpty) {
    say('No map layers are switched on.');
    return;
  }
  final downloader = ref.read(tileDownloaderProvider);
  final bounds = camera.visibleBounds;
  final minZoom = math.max(1, camera.zoom.floor());
  var maxZoom = minZoom + 3;
  int count() => downloader.estimateTileCount(
      bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, layers: layers);
  var tiles = count();
  while (tiles > downloader.maxTiles && maxZoom > minZoom) {
    maxZoom--;
    tiles = count();
  }
  if (tiles > downloader.maxTiles) {
    say('This area is too large to download — zoom in first.');
    return;
  }
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.download_for_offline_outlined),
      title: const Text('Download this area?'),
      content: Text(
        'The area visible on the map, zoom $minZoom–$maxZoom: about $tiles tiles. '
        'Please download only what you need — the map servers are run by volunteers.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Download')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final progress = ValueNotifier<(int, int)>((0, tiles));
  final cancel = TileDownloadCancelToken();
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(progress: progress, onCancel: cancel.cancel),
  );
  try {
    final failed = await downloader.downloadArea(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      layers: layers,
      cancel: cancel,
      onProgress: (done, total) => progress.value = (done, total),
    );
    say(cancel.isCancelled
        ? 'Download cancelled.'
        : failed == 0
            ? 'Map area saved for offline use.'
            : 'Map area saved; $failed tiles could not be downloaded.');
  } on TileDownloadLimitException catch (e) {
    say(e.toString());
  } catch (e) {
    say('Download failed: $e');
  } finally {
    nav.pop();
    progress.dispose();
    ref.invalidate(tileCacheSizeProvider);
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress, required this.onCancel});
  final ValueNotifier<(int, int)> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Downloading map'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (context, p, _) {
            final (done, total) = p;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: total == 0 ? null : done / total),
              const SizedBox(height: 12),
              Text('$done of $total tiles'),
            ]);
          },
        ),
        actions: [TextButton(onPressed: onCancel, child: const Text('Cancel'))],
      );
}

/// "123 MB" style size.
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} kB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}
