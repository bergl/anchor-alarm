import '../../domain/models.dart';

/// Action ids delivered by [NotificationService.actions].
abstract final class NotificationActions {
  static const silence = 'silence';
  static const open = 'open';
}

/// System notifications for alerts (shown in background, on lock screen and
/// mirrored to smartwatches).
abstract class NotificationService {
  Future<void> init();

  /// Asks for notification permission (Android 13+, iOS). Returns granted.
  Future<bool> requestPermission();

  /// Shows or replaces the alert notification for [reason].
  /// Alarms use the high-importance alarm channel with full-screen intent
  /// (Android) / time-sensitive interruption level (iOS) and a "Silence" action.
  Future<void> showAlert({
    required AlertReason reason,
    required String title,
    required String body,
  });

  /// Informational notification (e.g. "Anchor watch resumed"), default importance.
  Future<void> showInfo({required String title, required String body});

  Future<void> cancelAlert(AlertReason reason);
  Future<void> cancelAll();

  /// Notification action taps (see [NotificationActions]).
  Stream<String> get actions;
}
