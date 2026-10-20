import 'dart:async';

import 'package:flutter/foundation.dart';

import 'firestore_remote_sync.dart';
import 'push_service.dart';
import 'remote_store.dart';

/// Everything remote monitoring needs. Created by `startFirebaseRemote`
/// only when the build carries a Firebase configuration; the app treats a
/// null [RemoteServices] as "Remote monitoring is not configured".
class RemoteServices {
  RemoteServices({
    required this.store,
    required this.local,
    required this.push,
    required this.sync,
    required this.platform,
  });

  final RemoteWatchStore store;
  final RemoteLocalStore local;
  final PushService push;
  final FirestoreRemoteSync sync;

  /// `android`, `ios`, `web` (written to the watcher document).
  final String platform;

  StreamSubscription<String>? _tokenSub;

  /// Token refresh → update every watcher document of this device.
  void keepTokensFresh() {
    _tokenSub = push.tokenRefresh.listen((token) async {
      for (final b in local.monitored) {
        try {
          await store.setTokens(b.watchId, [token]);
        } catch (e) {
          debugPrint('Token update for ${b.watchId} failed: $e');
        }
      }
    });
  }

  Future<void> dispose() async => _tokenSub?.cancel();
}
