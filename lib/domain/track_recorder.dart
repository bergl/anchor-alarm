import 'geo.dart';
import 'models.dart';

/// Decides which fixes are kept in the session track, so an overnight watch
/// stores a few thousand points instead of tens of thousands.
class TrackRecorder {
  TrackRecorder({
    this.minInterval = const Duration(seconds: 5),
    this.maxInterval = const Duration(seconds: 30),
    this.minMoveM = 3,
  });

  /// Never record more often than this.
  final Duration minInterval;

  /// Always record at least this often.
  final Duration maxInterval;

  /// Record earlier than [maxInterval] when moved at least this far.
  final double minMoveM;

  TrackPoint? _last;

  /// Returns the point to store, or null when the fix should be skipped.
  /// While [alarm] is true every fix after [minInterval] is kept.
  TrackPoint? offer(PositionFix fix, {bool alarm = false}) {
    if (fix.accuracyM > 100) return null;
    final last = _last;
    if (last != null) {
      final dt = fix.time.difference(last.time);
      if (dt < minInterval) return null;
      final moved = distanceM(last.position, fix.position);
      if (!alarm && dt < maxInterval && moved < minMoveM) return null;
    }
    return _last = TrackPoint(fix.position, fix.time, fix.accuracyM);
  }
}
