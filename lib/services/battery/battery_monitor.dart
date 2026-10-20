class BatteryReading {
  const BatteryReading({required this.levelPct, required this.charging});
  final int levelPct;
  final bool charging;
}

abstract class BatteryMonitor {
  /// Emits the current reading immediately and then on changes / periodically.
  /// Emits nothing on platforms where battery state is unknown.
  Stream<BatteryReading> get readings;
}
