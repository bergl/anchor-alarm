/// Device compass heading (degrees true/magnetic, 0..360), used to estimate
/// the bow direction when the anchor is set from where the boat settles.
abstract class HeadingSource {
  /// Whether a compass is available on this platform/device.
  Future<bool> get available;

  /// Heading stream; emits null when the reading is unavailable.
  Stream<double?> get heading;
}
