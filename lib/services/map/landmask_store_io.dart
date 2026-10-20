import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'landmask_store.dart';

/// Masks as small JSON files (≈ 6 KB) under `<app support>/landmask/`.
/// Land does not move, so they never expire.
LandMaskStore createLandMaskStore() => FileLandMaskStore();

class FileLandMaskStore implements LandMaskStore {
  FileLandMaskStore({this.dir});

  /// Directory override (tests); defaults to `<app support>/landmask`.
  final Future<Directory> Function()? dir;
  Future<Directory>? _root;

  Future<Directory> get root => _root ??= () async {
        final custom = dir;
        if (custom != null) return custom();
        final support = await getApplicationSupportDirectory();
        return Directory(p.join(support.path, 'landmask'));
      }();

  Future<File> _file(String key) async =>
      File(p.join((await root).path, '${key.replaceAll(RegExp(r'[^0-9A-Za-z_.-]'), '_')}.json'));

  @override
  Future<Object?> read(String key) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> json) async {
    try {
      final f = await _file(key);
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(json), flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // Best effort: the mask is just fetched again next time.
    }
  }
}
