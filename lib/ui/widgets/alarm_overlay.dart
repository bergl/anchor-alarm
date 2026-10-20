import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';

/// Full-screen pulsing alarm shown while the alarm is ringing.
class AlarmOverlay extends ConsumerStatefulWidget {
  const AlarmOverlay({super.key, required this.onStopWatch});

  final VoidCallback onStopWatch;

  @override
  ConsumerState<AlarmOverlay> createState() => _AlarmOverlayState();
}

class _AlarmOverlayState extends ConsumerState<AlarmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(watchControllerProvider);
    final unit = ref.watch(settingsProvider.select((x) => x.distanceUnit));
    final snap = s.snapshot;
    final c = AnchorColors.of(context);
    final alarms = (snap?.reasons ?? const <AlertReason>{})
        .where((r) => r.isAlarm)
        .toList();
    final main = alarms.isEmpty ? AlertReason.drag : alarms.first;
    final controller = ref.read(watchControllerProvider.notifier);
    final boat = snap?.position ?? s.fix?.position;
    final fg = c.night ? Colors.black : Colors.white;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => ColoredBox(
        color: Color.lerp(
          c.alarm,
          c.night ? Colors.black : const Color(0xFF7F0000),
          _pulse.value * 0.6,
        )!,
        child: child,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.notifications_active, size: 72, color: fg),
              const SizedBox(height: 8),
              Text(
                alertTitle(main),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              for (final r in alarms.skip(1))
                Text(alertTitle(r),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontSize: 20)),
              if (snap?.distanceM != null) ...[
                const SizedBox(height: 16),
                Text(
                  formatDistance(snap!.distanceM, unit),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'from anchor · alarm at ${formatDistance(snap.radiusM, unit)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontSize: 18),
                ),
              ],
              const Spacer(),
              SizedBox(
                height: 120,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: fg,
                    foregroundColor: c.alarm,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: controller.acknowledge,
                  child: const Text(
                    'SILENCE',
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: fg,
                        side: BorderSide(color: fg),
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: widget.onStopWatch,
                      child: const Text('Stop watch'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: fg,
                        side: BorderSide(color: fg),
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: boat == null
                          ? null
                          : () {
                              controller.moveAnchor(boat);
                              controller.acknowledge();
                            },
                      child: const Text('Re-anchor here'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
