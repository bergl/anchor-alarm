import '../../domain/models.dart';
import '../../domain/watch_engine.dart';

/// Publishes the anchor watch for remote monitoring. Backend not chosen yet
/// (see DESIGN.md); [NoopRemoteSync] is used until then.
abstract class RemoteSync {
  Future<void> publish(AnchorSession session, WatchSnapshot snapshot);
  Future<void> end(AnchorSession session);
}

class NoopRemoteSync implements RemoteSync {
  const NoopRemoteSync();
  @override
  Future<void> publish(AnchorSession session, WatchSnapshot snapshot) async {}
  @override
  Future<void> end(AnchorSession session) async {}
}
