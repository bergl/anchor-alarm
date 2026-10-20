import 'dart:async';

/// A push message received while the app is in the foreground.
class RemotePush {
  const RemotePush({
    required this.kind,
    required this.watchId,
    this.title,
    this.body,
    this.reason,
  });

  /// `alarm`, `lostContact`, `contactRestored` or `ended` (see the functions).
  final String kind;
  final String watchId;
  final String? title;
  final String? body;

  /// Alert reason name for alarms (`drag`, `gpsLost`, `criticalBattery`).
  final String? reason;

  static RemotePush? fromData(Map<String, Object?> data, {String? title, String? body}) {
    final watchId = data['watchId'];
    final kind = data['kind'];
    if (watchId is! String || kind is! String) return null;
    final reason = data['reason'];
    return RemotePush(
      kind: kind,
      watchId: watchId,
      title: title,
      body: body,
      reason: reason is String && reason.isNotEmpty ? reason : null,
    );
  }
}

/// Push notifications for monitoring devices (FCM).
abstract class PushService {
  /// Asks for notification permission. Returns whether pushes can be shown.
  Future<bool> requestPermission();

  /// This device's push token, or null when pushes are unavailable (web,
  /// emulator builds, permission denied, no Google Play services...).
  Future<String?> token();

  Stream<String> get tokenRefresh;

  /// Messages received while the app is in the foreground (the system does
  /// not show them then).
  Stream<RemotePush> get foreground;
}

class NoPushService implements PushService {
  const NoPushService();
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefresh => const Stream.empty();
  @override
  Stream<RemotePush> get foreground => const Stream.empty();
}
