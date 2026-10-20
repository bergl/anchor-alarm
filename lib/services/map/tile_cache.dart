/// Offline map tiles: [CachingTileProvider], [TileCache] and [TileDownloader].
///
/// On mobile tiles are cached on disk; on the web the browser HTTP cache is
/// used and area download is not supported ([TileDownloader.supported]).
library;

export 'tile_cache_io.dart' if (dart.library.js_interop) 'tile_cache_web.dart';
export 'tile_layer_spec.dart';
