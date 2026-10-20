import 'package:flutter/foundation.dart';

import 'alarm/alarm_output.dart';
import 'alarm/audio_alarm_output.dart';
import 'alarm/local_notification_service.dart';
import 'alarm/notification_service.dart';
import 'battery/battery_monitor.dart';
import 'battery/battery_plus_monitor.dart';
import 'failsafe/failsafe.dart';
import 'heading/device_heading_source.dart';
import 'heading/heading_source.dart';
import 'location/geolocator_location_source.dart';
import 'location/location_source.dart';

/// The real device services, chosen for the current platform.
class PlatformServices {
  PlatformServices({
    required this.location,
    required this.heading,
    required this.alarm,
    required this.notifications,
    required this.battery,
    required this.failsafe,
  });

  final LocationSource location;
  final HeadingSource heading;
  final AlarmOutput alarm;
  final NotificationService notifications;
  final BatteryMonitor battery;
  final Failsafe failsafe;

  /// Initialises services that need it. Never throws; a failing service
  /// degrades to a no-op (e.g. notifications unsupported in a browser).
  Future<void> init() async {
    await Future.wait([
      _guard('notifications', notifications.init),
      _guard('alarm', alarm.init),
    ]);
  }

  static Future<void> _guard(String name, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('PlatformServices: $name init failed: $e');
    }
  }
}

/// Creates the services for this platform.
///
/// * Android/iOS: geolocator GPS, device compass, audioplayers alarm,
///   flutter_local_notifications, battery_plus, native fail-safe (Android).
/// * Web: geolocator (browser geolocation, foreground only), no compass,
///   HTML audio alarm, browser notifications through the plugin's service
///   worker (silently disabled where unsupported), battery_plus (Chromium
///   only; emits nothing elsewhere), no-op fail-safe.
PlatformServices createPlatformServices() {
  final mobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  return PlatformServices(
    location: GeolocatorLocationSource(),
    heading: mobile ? DeviceHeadingSource() : const NoHeadingSource(),
    alarm: AudioAlarmOutput(),
    notifications: LocalNotificationService(),
    battery: BatteryPlusMonitor(),
    failsafe: Failsafe(),
  );
}
