import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../domain/models.dart';
import 'location_source.dart';

/// The phone's own GPS via `geolocator`.
///
/// Background behaviour:
/// * Android: with `watch(background: true)` geolocator starts its own
///   foreground service (type `location`) with a persistent notification and
///   a partial wake lock. That service keeps the process and therefore the
///   Dart isolate alive while the screen is off, so the watch engine, the
///   alarm sound and notifications keep running.
/// * iOS: background location updates (requires `UIBackgroundModes/location`
///   and ideally "Always" permission) keep the app running while locked; the
///   blue status-bar pill is shown.
/// * Web: foreground only; the browser stops delivering fixes when the tab is
///   hidden.
class GeolocatorLocationSource implements LocationSource {
  GeolocatorLocationSource({this.androidInterval = const Duration(seconds: 1)});

  final Duration androidInterval;

  @override
  String get label => 'Phone GPS';

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // ---------------------------------------------------------------- permission

  /// Permission flow.
  ///
  /// Step 1 – "while in use": `Geolocator.requestPermission()` shows the
  /// standard system dialog (Android: precise/approximate + "While using the
  /// app"/"Only this time"; iOS: "Allow While Using App"/"Allow Once").
  ///
  /// Step 2 – "always" (only when [background] is true and step 1 succeeded):
  /// * Android 10 (API 29): a second runtime dialog offering
  ///   "Allow all the time".
  /// * Android 11+ (API 30+): the system does not show a dialog; requesting
  ///   ACCESS_BACKGROUND_LOCATION opens the app's location-permission
  ///   settings page where the user must pick "Allow all the time". The UI
  ///   should explain this *before* calling us (Google Play policy also
  ///   requires a prominent in-app disclosure first).
  /// * iOS: `requestAlwaysAuthorization` shows the "Change to Always Allow"
  ///   upgrade prompt. iOS shows it at most once; afterwards the user must
  ///   change it in Settings. iOS may also grant "provisional always" and ask
  ///   the user later while the app runs in the background.
  /// Both use `permission_handler`'s `Permission.locationAlways`, because
  /// geolocator on iOS only ever asks for "when in use".
  ///
  /// If the upgrade is refused we still return [LocationPermissionResult.whileInUse]:
  /// the watch works while the app is open, and on Android the foreground
  /// service keeps it running in the background anyway (a foreground service
  /// started while the app is visible may use "while in use" location).
  @override
  Future<LocationPermissionResult> requestPermission({bool background = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationPermissionResult.serviceDisabled;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
        perm = await Geolocator.requestPermission();
      }

      switch (perm) {
        case LocationPermission.deniedForever:
          return LocationPermissionResult.deniedForever;
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return LocationPermissionResult.denied;
        case LocationPermission.always:
          return LocationPermissionResult.always;
        case LocationPermission.whileInUse:
          break;
      }

      if (!background || kIsWeb) return LocationPermissionResult.whileInUse;

      if (_isAndroid || _isIOS) {
        try {
          final status = await ph.Permission.locationAlways.request();
          if (status.isGranted) return LocationPermissionResult.always;
        } catch (e) {
          debugPrint('locationAlways request failed: $e');
        }
        // Re-check: on iOS the result of the upgrade prompt is reported
        // asynchronously and geolocator's view is authoritative.
        final after = await Geolocator.checkPermission();
        if (after == LocationPermission.always) return LocationPermissionResult.always;
      }
      return LocationPermissionResult.whileInUse;
    } catch (e) {
      debugPrint('Location permission request failed: $e');
      return LocationPermissionResult.denied;
    }
  }

  // ------------------------------------------------------------------- stream

  LocationSettings _settings({required bool background}) {
    if (_isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: androidInterval,
        foregroundNotificationConfig: background
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Anchor watch active',
                notificationText: 'Monitoring your anchor position',
                notificationChannelName: 'Anchor watch',
                notificationIcon: AndroidResource(name: 'ic_stat_anchor', defType: 'drawable'),
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    if (_isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: background,
        showBackgroundLocationIndicator: background,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0);
  }

  @override
  Stream<PositionFix> watch({bool background = false}) {
    return Geolocator.getPositionStream(locationSettings: _settings(background: background))
        .map(_toFix);
  }

  @override
  Future<PositionFix?> currentFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: _isAndroid
            ? AndroidSettings(accuracy: LocationAccuracy.best, timeLimit: const Duration(seconds: 8))
            : const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 8)),
      );
      return _toFix(p);
    } catch (_) {
      try {
        final last = kIsWeb ? null : await Geolocator.getLastKnownPosition();
        return last == null ? null : _toFix(last);
      } catch (_) {
        return null;
      }
    }
  }

  /// Accuracy assumed when the platform does not report one.
  static const double unknownAccuracyM = 15;

  static PositionFix _toFix(Position p) {
    final speedOk = p.speed.isFinite && p.speed >= 0;
    final headingOk = p.heading.isFinite && p.heading >= 0;
    return PositionFix(
      position: LatLng(p.latitude, p.longitude),
      // Some sources (mock locations, external receivers, browsers) report 0
      // when accuracy is unknown; assume a typical phone fix rather than
      // discarding the position.
      accuracyM: p.accuracy.isFinite && p.accuracy > 0 ? p.accuracy : unknownAccuracyM,
      time: p.timestamp,
      speedMps: speedOk ? p.speed : null,
      // geolocator reports -1 (iOS) / 0 without hasBearing (Android) when the
      // course is unknown.
      courseDeg: headingOk && (p.heading > 0 || speedOk && p.speed > 0.3) ? p.heading % 360 : null,
      source: FixSource.device,
    );
  }
}
