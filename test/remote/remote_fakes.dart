import 'dart:async';

import 'package:anchor_alarm/app/providers.dart';
import 'package:anchor_alarm/app/remote_controllers.dart';
import 'package:anchor_alarm/services/remote/firestore_remote_sync.dart';
import 'package:anchor_alarm/services/remote/push_service.dart';
import 'package:anchor_alarm/services/remote/remote_models.dart';
import 'package:anchor_alarm/services/remote/remote_services.dart';
import 'package:anchor_alarm/services/remote/remote_store.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// In-memory [RemoteWatchStore]: records writes, serves watches from
/// controllers the test drives.
class FakeRemoteStore implements RemoteWatchStore {
  final puts = <(String, RemoteWatchWrite)>[];
  final stops = <(String, String)>[];
  final joins = <(String, String, List<String>)>[];
  final leaves = <String>[];
  final tokenUpdates = <(String, List<String>)>[];

  /// Watch ids that accept this share key (join succeeds only with it).
  final keys = <String, String>{};
  final _streams = <String, StreamController<RemoteWatch>>{};

  bool signInFails = false;
  int signIns = 0;
  Object? putError;
  RemoteException? joinError;

  StreamController<RemoteWatch> controller(String watchId) =>
      _streams.putIfAbsent(watchId, StreamController<RemoteWatch>.broadcast);

  void emit(RemoteWatch w) => controller(w.id).add(w);
  void fail(String watchId, RemoteException e) => controller(watchId).addError(e);

  @override
  Future<String> signIn() async {
    signIns++;
    if (signInFails) throw const RemoteException(RemoteErrorKind.offline);
    return 'owner-uid';
  }

  @override
  Future<void> putWatch(String watchId, RemoteWatchWrite data) async {
    puts.add((watchId, data));
    final e = putError;
    if (e != null) throw e;
  }

  @override
  Future<void> stopSharing(String watchId, {required String newShareKey, required DateTime endedAt}) async {
    stops.add((watchId, newShareKey));
  }

  @override
  Future<void> join(String watchId, String shareKey,
      {required List<String> fcmTokens, required String platform, String? name}) async {
    final e = joinError;
    if (e != null) throw e;
    if (keys[watchId] != shareKey) throw const RemoteException(RemoteErrorKind.accessDenied);
    joins.add((watchId, shareKey, fcmTokens));
  }

  @override
  Future<void> leave(String watchId) async => leaves.add(watchId);

  @override
  Future<void> setTokens(String watchId, List<String> fcmTokens) async =>
      tokenUpdates.add((watchId, fcmTokens));

  @override
  Stream<RemoteWatch> watch(String watchId) => controller(watchId).stream;
}

class FakePushService implements PushService {
  String? tokenValue = 'push-token-1';
  final refresh = StreamController<String>.broadcast();
  final messages = StreamController<RemotePush>.broadcast();
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<String?> token() async => tokenValue;
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<RemotePush> get foreground => messages.stream;
}

class RemoteTestEnv {
  RemoteTestEnv({List<MonitoredBoat> monitored = const []})
      : local = MemoryRemoteLocalStore(boatName: 'Kestrel', monitored: monitored) {
    sync = FirestoreRemoteSync(store: store, local: local, tzOffsetMin: () => 120);
    services = RemoteServices(
      store: store,
      local: local,
      push: push,
      sync: sync,
      platform: 'android',
    );
  }

  final store = FakeRemoteStore();
  final push = FakePushService();
  final MemoryRemoteLocalStore local;
  late final FirestoreRemoteSync sync;
  late final RemoteServices services;

  List<Override> get overrides => [
        remoteServicesProvider.overrideWithValue(services),
        remoteSyncProvider.overrideWithValue(sync),
      ];
}
