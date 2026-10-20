import 'package:flutter/foundation.dart';

/// Firebase configuration from compile-time defines — no generated
/// `firebase_options.dart` and no `google-services.json` /
/// `GoogleService-Info.plist` in the repository.
///
/// Build with `--dart-define-from-file=firebase.json` (see
/// `firebase.example.json` and docs/FIREBASE_SETUP.md). Without the defines
/// remote monitoring is switched off and the app works exactly as before.
///
/// For local development against the Firebase Emulator Suite:
/// `--dart-define=USE_FIREBASE_EMULATOR=true` (optionally
/// `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` for the Android emulator).
/// The emulator uses the demo project `demo-anchor-alarm` and needs no keys.
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.appIdAndroid,
    required this.appIdIos,
    required this.appIdWeb,
    required this.projectId,
    required this.messagingSenderId,
    required this.storageBucket,
    required this.iosBundleId,
    required this.webAuthDomain,
    required this.vapidKey,
    required this.useEmulator,
    required this.emulatorHost,
    this.apiKeyAndroid = '',
    this.apiKeyIos = '',
    this.apiKeyWeb = '',
  });

  /// Reads the `FIREBASE_*` defines.
  factory FirebaseConfig.fromEnvironment() => const FirebaseConfig(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        apiKeyAndroid: String.fromEnvironment('FIREBASE_API_KEY_ANDROID'),
        apiKeyIos: String.fromEnvironment('FIREBASE_API_KEY_IOS'),
        apiKeyWeb: String.fromEnvironment('FIREBASE_API_KEY_WEB'),
        appIdAndroid: String.fromEnvironment('FIREBASE_APP_ID_ANDROID'),
        appIdIos: String.fromEnvironment('FIREBASE_APP_ID_IOS'),
        appIdWeb: String.fromEnvironment('FIREBASE_APP_ID_WEB'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
        webAuthDomain: String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN'),
        vapidKey: String.fromEnvironment('FIREBASE_VAPID_KEY'),
        useEmulator: bool.fromEnvironment('USE_FIREBASE_EMULATOR'),
        emulatorHost: String.fromEnvironment('FIREBASE_EMULATOR_HOST', defaultValue: '127.0.0.1'),
      );

  /// Shared API key (Firebase creates one browser key per project; the
  /// per-platform keys below override it when set).
  final String apiKey;
  final String apiKeyAndroid;
  final String apiKeyIos;
  final String apiKeyWeb;
  final String appIdAndroid;
  final String appIdIos;
  final String appIdWeb;
  final String projectId;
  final String messagingSenderId;
  final String storageBucket;
  final String iosBundleId;
  final String webAuthDomain;

  /// Web push key pair (Cloud Messaging → Web configuration). Web push is
  /// not used yet (see DESIGN.md); kept so builds can carry it.
  final String vapidKey;
  final bool useEmulator;
  final String emulatorHost;

  static const emulatorProjectId = 'demo-anchor-alarm';
  static const firestoreEmulatorPort = 8080;
  static const authEmulatorPort = 9099;

  /// The app id for [platform], or '' when this build has none.
  String appIdFor(RemotePlatform platform) => switch (platform) {
        RemotePlatform.android => appIdAndroid,
        RemotePlatform.ios => appIdIos,
        RemotePlatform.web => appIdWeb,
        RemotePlatform.other => '',
      };

  String apiKeyFor(RemotePlatform platform) {
    final specific = switch (platform) {
      RemotePlatform.android => apiKeyAndroid,
      RemotePlatform.ios => apiKeyIos,
      RemotePlatform.web => apiKeyWeb,
      RemotePlatform.other => '',
    };
    return specific.isNotEmpty ? specific : apiKey;
  }

  /// Whether remote monitoring can run on [platform] with this build.
  bool isConfiguredFor(RemotePlatform platform) {
    if (platform == RemotePlatform.other) return false;
    if (useEmulator) return true;
    return apiKeyFor(platform).isNotEmpty &&
        appIdFor(platform).isNotEmpty &&
        projectId.isNotEmpty &&
        messagingSenderId.isNotEmpty;
  }

  /// Options for `Firebase.initializeApp`, as plain values (kept free of the
  /// Firebase types so this file is testable without plugins).
  /// Null when not configured for [platform].
  FirebaseOptionValues? optionsFor(RemotePlatform platform) {
    if (!isConfiguredFor(platform)) return null;
    if (useEmulator) {
      final p = switch (platform) {
        RemotePlatform.ios => 'ios',
        RemotePlatform.android => 'android',
        _ => 'web',
      };
      // Same placeholder shape firebase_core uses for demo projects.
      return FirebaseOptionValues(
        apiKey: 'ADemoProjectApiKey000000000000000000000',
        appId: '1:1:$p:1',
        messagingSenderId: '1',
        projectId: emulatorProjectId,
      );
    }
    return FirebaseOptionValues(
      apiKey: apiKeyFor(platform),
      appId: appIdFor(platform),
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      iosBundleId: platform == RemotePlatform.ios && iosBundleId.isNotEmpty ? iosBundleId : null,
      authDomain: platform == RemotePlatform.web
          ? (webAuthDomain.isNotEmpty ? webAuthDomain : '$projectId.firebaseapp.com')
          : null,
    );
  }
}

/// Values for `FirebaseOptions`.
class FirebaseOptionValues {
  const FirebaseOptionValues({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.storageBucket,
    this.iosBundleId,
    this.authDomain,
  });

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? storageBucket;
  final String? iosBundleId;
  final String? authDomain;
}

enum RemotePlatform { android, ios, web, other }

RemotePlatform get currentRemotePlatform {
  if (kIsWeb) return RemotePlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => RemotePlatform.android,
    TargetPlatform.iOS => RemotePlatform.ios,
    _ => RemotePlatform.other,
  };
}

/// Shown wherever remote monitoring would appear in a build without Firebase.
const remoteNotConfiguredMessage = 'Remote monitoring is not configured in this build.';
