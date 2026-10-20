import 'package:flutter/material.dart';

import '../../app/format.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';

/// Big coloured SAFE / WARNING / ALARM banner with the reasons in plain words.
/// Flashes while in alarm.
class StateBanner extends StatefulWidget {
  const StateBanner({
    super.key,
    required this.state,
    required this.reasons,
    this.waitingForGps = false,
    this.trailing,
  });

  final WatchState state;
  final Set<AlertReason> reasons;

  /// No position yet (e.g. just after a restart). Shown instead of SAFE so the
  /// screen never claims the boat is safe without knowing where it is.
  final bool waitingForGps;
  final Widget? trailing;

  @override
  State<StateBanner> createState() => _StateBannerState();
}

class _StateBannerState extends State<StateBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StateBanner old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.state == WatchState.alarm) {
      if (!_flash.isAnimating) _flash.repeat(reverse: true);
    } else {
      _flash
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AnchorColors.of(context);
    final waiting = widget.waitingForGps && widget.state == WatchState.safe;
    final base = waiting ? c.neutral : c.forState(widget.state);
    final reasons = widget.reasons.toList()
      ..sort((a, b) => (b.isAlarm ? 1 : 0) - (a.isAlarm ? 1 : 0));
    final icon = waiting ? Icons.gps_not_fixed : switch (widget.state) {
      WatchState.safe => Icons.check_circle,
      WatchState.warning => Icons.warning_amber_rounded,
      WatchState.alarm => Icons.notifications_active,
      WatchState.inactive => Icons.anchor,
    };
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          color: Color.lerp(base, c.night ? Colors.black : Colors.white, _flash.value * 0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: child,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: c.onState),
        child: Row(
          children: [
            Icon(icon, color: c.onState, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    waiting ? 'WAITING FOR GPS' : stateLabel(widget.state),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      height: 1.1,
                    ),
                  ),
                  if (waiting)
                    const Text('The alarm sounds if no position arrives.',
                        style: TextStyle(fontSize: 15)),
                  for (final r in reasons)
                    Text(alertShort(r), style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            ?widget.trailing,
          ],
        ),
      ),
    );
  }
}
