import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'offline_area_history.dart';
import 'tile_cache_io.dart';

/// History stored as `offline_areas.json` in the tile cache directory, so
/// clearing the cache also forgets the downloaded areas.
OfflineAreaHistory createOfflineAreaHistory(TileCache cache) =>
    FileOfflineAreaHistory(() async => File(p.join((await cache.root).path, 'offline_areas.json')));

class FileOfflineAreaHistory implements OfflineAreaHistory {
  FileOfflineAreaHistory(this.file);
  final Future<File> Function() file;

  @override
  Future<List<OfflineAreaRecord>> load() async {
    try {
      final f = await file();
      if (!await f.exists()) return [];
      final j = jsonDecode(await f.readAsString());
      if (j is! List) return [];
      return [
        for (final e in j) ?OfflineAreaRecord.fromJson(e),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<OfflineAreaRecord> records) async {
    try {
      final f = await file();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final r in records) r.toJson()]), flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // Best effort: without history the area is just downloaded again.
    }
  }
}
