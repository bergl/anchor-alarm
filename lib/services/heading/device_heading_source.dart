import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_rotation_sensor/flutter_rotation_sensor.dart';

import 'heading_source.dart';

/// Device compass via `flutter_rotation_sensor` (Android rotation-vector
/// sensor, iOS Core Motion device attitude referenced to magnetic north).
///
/// The heading is the direction the top edge of the phone points in the
/// current display orientation, in degrees magnetic (0..360). It is the
/// tilt-compensated azimuth, so it works with the phone held upright or flat.
///
/// Not used on web: browser orientation events need a user-gesture permission
/// prompt and are unreliable for this purpose; [NoHeadingSource] is used there.
class DeviceHeadingSource implements HeadingSource {
  DeviceHeadingSource({this.samplingPeriod = const Duration(milliseconds: 200)});

  final Duration samplingPeriod;
  Stream<double?>? _stream;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) &&
      RotationSensor.isPlatformSupported;

  @override
  Future<bool> get available async {
    if (!_supported) return false;
    // The plugin reports a missing sensor as a stream error; probe once.
    try {
      final first = await heading.first.timeout(const Duration(seconds: 2));
      return first != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<double?> get heading {
    if (!_supported) return Stream<double?>.value(null);
    return _stream ??= _create();
  }

  Stream<double?> _create() {
    RotationSensor.samplingPeriod = samplingPeriod;
    RotationSensor.referenceFrame = ReferenceFrame.magneticNorth;
    late StreamController<double?> controller;
    StreamSubscription<OrientationEvent>? sub;
    controller = StreamController<double?>.broadcast(
      onListen: () {
        sub = RotationSensor.orientationStream.listen(
          (e) {
            final az = e.eulerAngles.azimuth;
            if (!az.isFinite) {
              controller.add(null);
              return;
            }
            final deg = (az * 180 / math.pi) % 360;
            controller.add(deg < 0 ? deg + 360 : deg);
          },
          onError: (Object _) => controller.add(null),
        );
      },
      onCancel: () async {
        // Last listener gone: stop the native sensor.
        await sub?.cancel();
        sub = null;
      },
    );
    return controller.stream;
  }
}

/// For platforms without a compass (web, desktop).
class NoHeadingSource implements HeadingSource {
  const NoHeadingSource();

  @override
  Future<bool> get available async => false;

  @override
  Stream<double?> get heading => Stream<double?>.value(null);
}
