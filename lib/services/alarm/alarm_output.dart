/// Local, in-app alerting: loud looping sound, vibration, keeping the device awake.
abstract class AlarmOutput {
  Future<void> init();

  /// Start the alarm (looping sound at full volume, repeating vibration).
  /// Must work while the app is in the background (iOS playback session,
  /// Android alarm audio usage). Calling it while already ringing is a no-op.
  Future<void> startAlarm({required String sound, required bool vibrate});

  Future<void> stopAlarm();

  /// Short non-looping warning chime (+ short vibration).
  Future<void> chime({required bool vibrate});

  bool get isRinging;
}
