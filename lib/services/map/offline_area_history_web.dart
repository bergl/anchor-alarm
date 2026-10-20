import 'offline_area_history.dart';
import 'tile_cache_web.dart';

/// Web: no area download, so nothing to remember.
OfflineAreaHistory createOfflineAreaHistory(TileCache cache) => _NoopHistory();

class _NoopHistory implements OfflineAreaHistory {
  @override
  Future<List<OfflineAreaRecord>> load() async => const [];

  @override
  Future<void> save(List<OfflineAreaRecord> records) async {}
}
