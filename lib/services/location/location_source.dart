import '../../domain/models.dart';

enum LocationPermissionResult {
  /// "Always" (background) permission.
  always,

  /// Only while the app is in use; background watch may stop when locked.
  whileInUse,
  denied,
  deniedForever,

  /// Location services are switched off on the device.
  serviceDisabled,
}

/// A stream of position fixes: the device GPS, the simulator, or later NMEA.
abstract class LocationSource {
  /// Human-readable name shown in the UI ("Phone GPS", "Simulator").
  String get label;

  /// Asks for permission. [background] requests "Always" where supported.
  Future<LocationPermissionResult> requestPermission({bool background = false});

  /// Continuous fixes. With [background] the platform keeps delivering
  /// while the app is in the background (Android foreground service with a
  /// persistent notification, iOS background location updates).
  /// Cancelling the subscription stops the updates.
  Stream<PositionFix> watch({bool background = false});

  /// One fix, or null if none is available within a few seconds.
  Future<PositionFix?> currentFix();
}
