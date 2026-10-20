import 'package:flutter_map/flutter_map.dart';

import 'tile_layer_spec.dart';

/// Web: no own tile store; the browser HTTP cache keeps recently seen tiles.
class TileCache {
  TileCache();

  static const bool supported = false;

  Future<int> sizeBytes() async => 0;
  Future<void> clear() async {}
  void close() {}
}

/// On the web this is flutter_map's [NetworkTileProvider] (browser cache).
/// The User-Agent header cannot be set by web pages.
class CachingTileProvider extends NetworkTileProvider {
  CachingTileProvider({required this.layer, required this.cache});

  final TileLayerSpec layer;
  final TileCache cache;
}

/// Area download is not available on the web ([supported] is false).
class TileDownloader {
  TileDownloader(this.cache, {this.maxTiles = maxDownloadTiles});

  final TileCache cache;
  final int maxTiles;

  static const bool supported = false;

  int estimateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required List<TileLayerSpec> layers,
  }) =>
      countTilesInArea(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, layers: layers);

  Future<int> downloadArea({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required List<TileLayerSpec> layers,
    void Function(int done, int total)? onProgress,
    TileDownloadCancelToken? cancel,
  }) =>
      Future.error(UnsupportedError('Offline area download is not available on the web'));

  Future<int> cacheSizeBytes() async => 0;
  Future<void> clearCache() async {}
}
