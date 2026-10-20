import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform fail-safes that keep a watch from silently dying.
///
/// Android: while a watch is active a flag is stored in native
/// SharedPreferences; if the phone reboots, a BOOT_COMPLETED receiver sees the
/// flag and posts a high-priority "Anchor watch interrupted by restart — tap
/// to resume" notification. Battery-optimisation exemption keeps Doze and
/// OEM task killers from stopping the location foreground service.
///
/// iOS/web: nothing equivalent exists; all calls are no-ops.
abstract class Failsafe {
  /// Records whether a watch is running (call on start and on stop).
  Future<void> setWatchActive(bool active);

  /// Opens the system dialog asking to exempt the app from battery
  /// optimisation (Android). No-op elsewhere.
  Future<void> requestIgnoreBatteryOptimizations();

  /// Whether the app is exempt from battery optimisation. Always true where
  /// the concept does not exist (iOS, web).
  Future<bool> isIgnoringBatteryOptimizations();

  /// Creates the implementation for the current platform.
  factory Failsafe() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? AndroidFailsafe() : const NoopFailsafe();
}

class AndroidFailsafe implements Failsafe {
  static const _channel = MethodChannel('anchor_alarm/failsafe');

  @override
  Future<void> setWatchActive(bool active) async {
    try {
      await _channel.invokeMethod<void>('setWatchActive', {'active': active});
    } catch (e) {
      debugPrint('Failsafe.setWatchActive failed: $e');
    }
  }

  @override
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('Failsafe.requestIgnoreBatteryOptimizations failed: $e');
    }
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (e) {
      debugPrint('Failsafe.isIgnoringBatteryOptimizations failed: $e');
      return false;
    }
  }
}

class NoopFailsafe implements Failsafe {
  const NoopFailsafe();

  @override
  Future<void> setWatchActive(bool active) async {}

  @override
  Future<void> requestIgnoreBatteryOptimizations() async {}

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;
}
