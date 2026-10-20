export 'landmask_store_io.dart' if (dart.library.js_interop) 'landmask_store_web.dart';

/// Persistent cache of serialised water masks (`WaterMask.toJson`).
abstract class LandMaskStore {
  /// Null when missing or unreadable.
  Future<Object?> read(String key);
  Future<void> write(String key, Map<String, Object?> json);
}

/// Keeps masks for the lifetime of the app only (tests, web).
class MemoryLandMaskStore implements LandMaskStore {
  final entries = <String, Map<String, Object?>>{};

  @override
  Future<Object?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, Map<String, Object?> json) async => entries[key] = json;
}
