import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import 'battery_monitor.dart';

/// Battery level/charging via battery_plus.
///
/// Emits a reading immediately on listen, on every charging-state change and
/// every [period]. If the platform cannot report the battery (desktop
/// without battery, browsers without the Battery Status API such as Firefox
/// and Safari) nothing is emitted and no error is raised.
class BatteryPlusMonitor implements BatteryMonitor {
  BatteryPlusMonitor({Battery? battery, this.period = const Duration(seconds: 60)})
      : _battery = battery ?? Battery();

  final Battery _battery;
  final Duration period;

  @override
  Stream<BatteryReading> get readings {
    late StreamController<BatteryReading> controller;
    Timer? timer;
    StreamSubscription<BatteryState>? stateSub;
    var supported = true;
    BatteryState? lastState;

    Future<void> emit() async {
      if (!supported || controller.isClosed) return;
      try {
        final level = await _battery.batteryLevel;
        final state = lastState ?? await _battery.batteryState;
        if (level < 0 || level > 100 || state == BatteryState.unknown && level == 0) {
          return;
        }
        if (!controller.isClosed) {
          controller.add(BatteryReading(
            levelPct: level,
            charging: state == BatteryState.charging || state == BatteryState.full ||
                state == BatteryState.connectedNotCharging,
          ));
        }
      } catch (e) {
        // Unsupported platform/browser: stop polling silently.
        debugPrint('Battery reading unavailable: $e');
        supported = false;
        timer?.cancel();
        await stateSub?.cancel();
      }
    }

    controller = StreamController<BatteryReading>(
      onListen: () {
        emit();
        timer = Timer.periodic(period, (_) => emit());
        try {
          stateSub = _battery.onBatteryStateChanged.listen(
            (s) {
              lastState = s;
              emit();
            },
            onError: (Object _) {},
          );
        } catch (_) {}
      },
      onCancel: () async {
        timer?.cancel();
        await stateSub?.cancel();
      },
    );
    return controller.stream;
  }
}
