import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tile_layer_spec.dart';

/// Disk cache of map tiles under
/// `getApplicationSupportDirectory()/tiles/<layerKey>/<z>/<x>/<y>.png`.
class TileCache {
  TileCache({
    this.rootDir,
    http.Client? client,
    this.maxAge = const Duration(days: 30),
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  /// Tiles older than this are refreshed when online; stale tiles are still
  /// served when the network is unavailable.
  final Duration maxAge;
  final Duration timeout;

  /// Cache directory override (tests); defaults to `<app support>/tiles`.
  final Future<Directory> Function()? rootDir;
  final http.Client _client;
  Future<Directory>? _root;

  static const headers = {'User-Agent': tileUserAgent};

  /// Whether this platform has a persistent tile cache.
  static const bool supported = true;

  Future<Directory> get root => _root ??= () async {
        final custom = rootDir;
        if (custom != null) return custom();
        final support = await getApplicationSupportDirectory();
        return Directory(p.join(support.path, 'tiles'));
      }();

  Future<File> _file(TileLayerSpec layer, int z, int x, int y) async =>
      File(p.join((await root).path, layer.key, '$z', '$x', '$y.png'));

  /// Whether a tile younger than [maxAge] is on disk.
  Future<bool> hasFresh(TileLayerSpec layer, int z, int x, int y) async {
    final f = await _file(layer, z, x, y);
    try {
      final stat = await f.stat();
      return stat.type == FileSystemEntityType.file &&
          DateTime.now().difference(stat.modified) < maxAge;
    } catch (_) {
      return false;
    }
  }

  /// Returns the tile bytes: fresh from disk, otherwise from the network
  /// (and stored), otherwise a stale tile from disk. Throws when none is
  /// available. [url] overrides the URL built from [layer].
  Future<Uint8List> load(TileLayerSpec layer, int z, int x, int y, {String? url}) async {
    final f = await _file(layer, z, x, y);
    FileStat? stat;
    try {
      stat = await f.stat();
      if (stat.type != FileSystemEntityType.file) stat = null;
    } catch (_) {
      stat = null;
    }
    if (stat != null && DateTime.now().difference(stat.modified) < maxAge) {
      try {
        return await f.readAsBytes();
      } catch (_) {
        // Fall through to the network.
      }
    }
    try {
      final bytes = await fetch(layer, z, x, y, url: url);
      await _write(f, bytes);
      return bytes;
    } catch (e) {
      // Offline or server error: a stale tile is better than none.
      if (stat != null) return f.readAsBytes();
      rethrow;
    }
  }

  /// Downloads a tile without touching the cache.
  Future<Uint8List> fetch(TileLayerSpec layer, int z, int x, int y, {String? url}) async {
    final res = await _client
        .get(Uri.parse(url ?? layer.url(z, x, y)), headers: headers)
        .timeout(timeout);
    // WMS servers report errors as HTTP 200 with an XML body: never cache that.
    final notImage = layer.isWms &&
        !(res.headers['content-type'] ?? 'image/').startsWith('image/');
    if (res.statusCode == 200 && res.bodyBytes.isNotEmpty && !notImage) return res.bodyBytes;
    if (layer.transparent && res.statusCode == 404) {
      return TileProvider.transparentImage;
    }
    throw http.ClientException('HTTP ${res.statusCode}', res.request?.url);
  }

  /// Downloads a tile into the cache unless a fresh copy is already there.
  Future<void> ensure(TileLayerSpec layer, int z, int x, int y) async {
    if (await hasFresh(layer, z, x, y)) return;
    final bytes = await fetch(layer, z, x, y);
    await _write(await _file(layer, z, x, y), bytes);
  }

  Future<void> _write(File f, Uint8List bytes) async {
    try {
      await f.parent.create(recursive: true);
      // Write to a temp file and rename so a crash never leaves half a tile.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // Cache write failures (disk full, ...) must not break the map.
    }
  }

  /// Total size of all cached tiles.
  Future<int> sizeBytes() async {
    final dir = await root;
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Deletes all cached tiles.
  Future<void> clear() async {
    final dir = await root;
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  void close() => _client.close();
}

/// flutter_map tile provider serving tiles from [TileCache] (disk first,
/// network fallback, stale tiles when offline).
class CachingTileProvider extends TileProvider {
  CachingTileProvider({required this.layer, required this.cache})
      : super(headers: Map.of(TileCache.headers));

  final TileLayerSpec layer;
  final TileCache cache;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedTileImage(
        cache: cache,
        layer: layer,
        z: coordinates.z,
        x: coordinates.x,
        y: coordinates.y,
        url: getTileUrl(coordinates, options),
      );
}

@immutable
class CachedTileImage extends ImageProvider<CachedTileImage> {
  const CachedTileImage({
    required this.cache,
    required this.layer,
    required this.z,
    required this.x,
    required this.y,
    required this.url,
  });

  final TileCache cache;
  final TileLayerSpec layer;
  final int z, x, y;
  final String url;

  @override
  Future<CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: 1,
        debugLabel: url,
      );

  Future<ui.Codec> _load(CachedTileImage key, ImageDecoderCallback decode) async {
    try {
      final bytes = await cache.load(layer, z, x, y, url: url);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // Do not keep the failure in the image cache: retry when visible again.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedTileImage &&
      other.layer.key == layer.key &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(layer.key, z, x, y);
}

/// "Download this area" for offline use.
class TileDownloader {
  TileDownloader(this.cache, {this.maxTiles = maxDownloadTiles});

  final TileCache cache;
  final int maxTiles;

  /// Whether area download is available on this platform.
  static const bool supported = true;

  int estimateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required List<TileLayerSpec> layers,
  }) =>
      countTilesInArea(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, layers: layers);

  /// Downloads all tiles of [layers] covering [bounds] into the cache,
  /// skipping tiles already cached and fresh. At most [maxDownloadParallel]
  /// requests run at once; throws [TileDownloadLimitException] when more than
  /// [maxTiles] tiles would be needed. Individual tile failures are skipped
  /// (counted as done). Returns the number of tiles that failed.
  Future<int> downloadArea({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required List<TileLayerSpec> layers,
    void Function(int done, int total)? onProgress,
    TileDownloadCancelToken? cancel,
  }) async {
    final total = countTilesInArea(
        bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, layers: layers);
    if (total > maxTiles) throw TileDownloadLimitException(total, maxTiles);

    final jobs = <(TileLayerSpec, TileXYZ)>[
      for (final layer in layers)
        for (final t in tilesInBounds(
            bounds, minZoom, maxZoom < layer.maxNativeZoom ? maxZoom : layer.maxNativeZoom))
          (layer, t),
    ].iterator;
    var done = 0;
    var failed = 0;
    onProgress?.call(0, total);

    Future<void> worker() async {
      while (!(cancel?.isCancelled ?? false) && jobs.moveNext()) {
        final (layer, t) = jobs.current;
        try {
          await cache.ensure(layer, t.z, t.x, t.y);
        } catch (_) {
          failed++;
        }
        done++;
        onProgress?.call(done, total);
      }
    }

    await Future.wait([for (var i = 0; i < maxDownloadParallel; i++) worker()]);
    return failed;
  }

  Future<int> cacheSizeBytes() => cache.sizeBytes();
  Future<void> clearCache() => cache.clear();
}
