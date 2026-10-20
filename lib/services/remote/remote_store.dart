import 'remote_models.dart';

/// Why a remote operation failed, in terms the UI can explain.
enum RemoteErrorKind {
  /// The share key is wrong or was rotated ("Stop sharing"), or the watch
  /// does not exist.
  accessDenied,

  /// No connection (or the backend is unavailable).
  offline,
  other,
}

class RemoteException implements Exception {
  const RemoteException(this.kind, [this.message = '']);
  final RemoteErrorKind kind;
  final String message;

  @override
  String toString() => 'RemoteException(${kind.name}${message.isEmpty ? '' : ': $message'})';
}

/// The cloud side of remote monitoring (Firestore in production, a fake in
/// tests). All writes may complete late (offline queue) — callers must not
/// await them inside the watch loop.
abstract class RemoteWatchStore {
  /// Signs in (anonymously) if needed; returns the user id.
  Future<String> signIn();

  /// Creates or updates `watches/{watchId}` (merge; `updatedAt` = server time).
  Future<void> putWatch(String watchId, RemoteWatchWrite data);

  /// "Stop sharing": rotates the share key (locks out every watcher), ends
  /// the watch and deletes the watcher documents.
  Future<void> stopSharing(String watchId, {required String newShareKey, required DateTime endedAt});

  /// Joins as a watcher with [shareKey]. Throws [RemoteException]
  /// (accessDenied when the key is wrong or the watch does not exist).
  Future<void> join(
    String watchId,
    String shareKey, {
    required List<String> fcmTokens,
    required String platform,
    String? name,
  });

  /// Removes this device's watcher document.
  Future<void> leave(String watchId);

  /// Replaces this device's push tokens on its watcher document.
  Future<void> setTokens(String watchId, List<String> fcmTokens);

  /// Live updates of a watch. Emits a [RemoteException] error when access
  /// is denied (e.g. after "Stop sharing").
  Stream<RemoteWatch> watch(String watchId);
}

/// Device-local remote state: share records (by session), boat name, and
/// the boats this device monitors.
abstract class RemoteLocalStore {
  ShareRecord? shareFor(String sessionId);
  Future<void> saveShare(ShareRecord record);

  String get boatName;
  Future<void> saveBoatName(String name);

  List<MonitoredBoat> get monitored;
  Future<void> saveMonitored(List<MonitoredBoat> boats);
}

class MemoryRemoteLocalStore implements RemoteLocalStore {
  MemoryRemoteLocalStore({this._boatName = '', List<MonitoredBoat> monitored = const []})
      : _monitored = List.of(monitored);

  final Map<String, ShareRecord> shares = {};
  String _boatName;
  List<MonitoredBoat> _monitored;

  @override
  ShareRecord? shareFor(String sessionId) => shares[sessionId];
  @override
  Future<void> saveShare(ShareRecord record) async => shares[record.sessionId] = record;
  @override
  String get boatName => _boatName;
  @override
  Future<void> saveBoatName(String name) async => _boatName = name;
  @override
  List<MonitoredBoat> get monitored => List.unmodifiable(_monitored);
  @override
  Future<void> saveMonitored(List<MonitoredBoat> boats) async => _monitored = List.of(boats);
}
