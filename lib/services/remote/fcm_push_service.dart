import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_service.dart';

/// Background / terminated-app push handler.
///
/// The functions send *notification* messages: Android shows them on the
/// app's `anchor_alarm` channel (created by LocalNotificationService at
/// every start, max importance, alarm audio) and iOS shows them as
/// time-sensitive alerts — without running any Dart. Nothing to do here;
/// registering a handler lets the plugin deliver data to the app later.
@pragma('vm:entry-point')
Future<void> anchorAlarmBackgroundMessage(RemoteMessage message) async {}

/// [PushService] on Firebase Cloud Messaging (Android, iOS).
///
/// Web push is not used: it would need a `firebase-messaging-sw.js` with the
/// project config next to the notifications plugin's service worker. The web
/// app alerts through the live view while the tab is open (DESIGN.md).
class FcmPushService implements PushService {
  FcmPushService(this.messaging);

  final FirebaseMessaging messaging;
  Stream<RemotePush>? _foreground;

  /// Registers the background handler. Call once at start-up.
  static void registerBackgroundHandler() {
    if (kIsWeb) return;
    FirebaseMessaging.onBackgroundMessage(anchorAlarmBackgroundMessage);
  }

  @override
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    try {
      final s = await messaging.requestPermission(alert: true, sound: true, badge: false);
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Push permission failed: $e');
      return false;
    }
  }

  @override
  Future<String?> token() async {
    if (kIsWeb) return null;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // The FCM token needs the APNs token first (push capability and an
        // APNs key in the Firebase project; see FIREBASE_SETUP.md).
        // It can take a moment after launch to arrive.
        String? apns;
        for (var i = 0; i < 5 && apns == null; i++) {
          apns = await messaging.getAPNSToken();
          if (apns == null) await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (apns == null) return null;
      }
      // Registration tokens are deprecated in favour of Firebase Installation
      // IDs (register() / onRegistered + `fids` on the server) but still
      // work; migrating is a follow-up (DESIGN.md).
      // ignore: deprecated_member_use
      return await messaging.getToken().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Push token unavailable: $e');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefresh =>
      // ignore: deprecated_member_use
      kIsWeb ? const Stream.empty() : messaging.onTokenRefresh;

  @override
  Stream<RemotePush> get foreground => _foreground ??= kIsWeb
      ? const Stream<RemotePush>.empty()
      : FirebaseMessaging.onMessage
          .map((m) => RemotePush.fromData(
                Map<String, Object?>.from(m.data),
                title: m.notification?.title,
                body: m.notification?.body,
              ))
          .where((p) => p != null)
          .cast<RemotePush>()
          .asBroadcastStream();
}
