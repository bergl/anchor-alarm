import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import 'fcm_push_service.dart';
import 'firebase_config.dart';
import 'firestore_remote_store.dart';
import 'firestore_remote_sync.dart';
import 'push_service.dart';
import 'remote_services.dart';
import 'sembast_remote_local_store.dart';

/// Initialises Firebase from [config] (explicit options — no
/// google-services.json / GoogleService-Info.plist). Returns null when this
/// build has no configuration for the platform or initialisation fails;
/// never throws.
Future<RemoteServices?> startFirebaseRemote({
  required FirebaseConfig config,
  required Database database,
}) async {
  final platform = currentRemotePlatform;
  final values = config.optionsFor(platform);
  if (values == null) return null;
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: values.apiKey,
        appId: values.appId,
        messagingSenderId: values.messagingSenderId,
        projectId: values.projectId,
        storageBucket: values.storageBucket,
        iosBundleId: values.iosBundleId,
        authDomain: values.authDomain,
      ),
    ).timeout(const Duration(seconds: 10));

    final firestore = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    if (config.useEmulator) {
      firestore.useFirestoreEmulator(config.emulatorHost, FirebaseConfig.firestoreEmulatorPort);
      await auth.useAuthEmulator(config.emulatorHost, FirebaseConfig.authEmulatorPort);
    }
    if (!kIsWeb) {
      // Offline persistence: writes made at anchor without signal are
      // queued and sent when the connection returns.
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 20 * 1024 * 1024,
      );
    }

    final PushService push;
    if (config.useEmulator || kIsWeb) {
      push = const NoPushService();
    } else {
      FcmPushService.registerBackgroundHandler();
      push = FcmPushService(FirebaseMessaging.instance);
    }

    final local = await SembastRemoteLocalStore.open(database);
    final store = FirestoreRemoteStore(firestore: firestore, auth: auth);
    final services = RemoteServices(
      store: store,
      local: local,
      push: push,
      sync: FirestoreRemoteSync(store: store, local: local),
      platform: platform.name,
    );
    services.keepTokensFresh();
    return services;
  } catch (e) {
    debugPrint('Remote monitoring unavailable: $e');
    return null;
  }
}
