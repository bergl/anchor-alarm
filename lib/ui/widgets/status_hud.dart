import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';
import '../ui_providers.dart';
import 'state_banner.dart';

/// Bottom card on the map: the watch status, or the "Drop anchor" button.
class StatusHud extends ConsumerWidget {
  const StatusHud({
    super.key,
    required this.onDropAnchor,
    required this.onAdjust,
    required this.onStop,
  });

  final VoidCallback onDropAnchor;
  final VoidCallback onAdjust;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watching = ref.watch(watchControllerProvider.select((s) => s.watching));
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: watching
              ? _WatchingStatus(onAdjust: onAdjust, onStop: onStop)
              : _IdleStatus(onDropAnchor: onDropAnchor),
        ),
      ),
    );
  }
}

class _IdleStatus extends ConsumerWidget {
  const _IdleStatus({required this.onDropAnchor});
  final VoidCallback onDropAnchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(watchControllerProvider);
    final unit = ref.watch(settingsProvider.select((x) => x.distanceUnit));
    final fix = s.fix;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(fix == null ? Icons.gps_not_fixed : Icons.gps_fixed,
                color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fix == null
                    ? 'Waiting for GPS…'
                    : '${s.sourceLabel.isEmpty ? 'GPS' : s.sourceLabel} · '
                        'accuracy ${formatAccuracy(fix.accuracyM, unit)}',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onDropAnchor,
          icon: const Icon(Icons.anchor, size: 28),
          label: const Text('Drop anchor'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
        ),
      ],
    );
  }
}

class _WatchingStatus extends ConsumerWidget {
  const _WatchingStatus({required this.onAdjust, required this.onStop});
  final VoidCallback onAdjust;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(watchControllerProvider);
    final unit = ref.watch(settingsProvider.select((x) => x.distanceUnit));
    final session = s.session!;
    final snap = s.snapshot;
    final theme = Theme.of(context);
    final now = snap?.time ?? DateTime.now();
    final radius = snap?.radiusM ?? session.radiusM;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StateBanner(
          state: snap?.state ?? WatchState.safe,
          reasons: snap?.reasons ?? const {},
        ),
        if (snap?.snoozedUntil != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SnoozeChip(until: snap!.snoozedUntil!, now: now),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _BigDistance(
                distanceM: snap?.distanceM,
                radiusM: radius,
                unit: unit,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Adjust radius or profile',
              iconSize: 28,
              onPressed: onAdjust,
              icon: const Icon(Icons.tune),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Stop watch',
              iconSize: 28,
              onPressed: onStop,
              icon: const Icon(Icons.stop),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Metric(Icons.explore, 'Bearing', formatBearing(snap?.bearingFromAnchorDeg)),
            _Metric(Icons.gps_fixed, 'GPS', formatAccuracy(snap?.accuracyM ?? s.fix?.accuracyM, unit)),
            _Metric(Icons.timer_outlined, 'Watch', formatDuration(session.duration(now))),
            _Metric(Icons.open_in_full, 'Max', formatDistance(snap?.maxDistanceM ?? session.maxDistanceM, unit)),
            _Metric(Icons.satellite_alt, 'Source', s.sourceLabel.isEmpty ? '–' : s.sourceLabel),
            const _BatteryMetric(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            session.profile.name,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _BigDistance extends StatelessWidget {
  const _BigDistance({required this.distanceM, required this.radiusM, required this.unit});
  final double? distanceM;
  final double radiusM;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Distance to anchor ${formatDistance(distanceM, unit)} '
          'of ${formatDistance(radiusM, unit)}',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: formatDistanceValue(distanceM, unit),
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w800, height: 1),
            ),
            TextSpan(
              text: ' / ${formatDistance(radiusM, unit)}',
              style: theme.textTheme.titleLarge,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text('$label ', style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _BatteryMetric extends ConsumerWidget {
  const _BatteryMetric();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(batteryProvider).value;
    if (b == null) return const SizedBox.shrink();
    final low = !b.charging && b.levelPct < 50;
    return _Metric(
      b.charging ? Icons.battery_charging_full : Icons.battery_std,
      'Battery',
      '${b.levelPct} %${low ? ' · plug in' : ''}',
    );
  }
}

/// "Snoozed 1:45" chip shown while a silenced alarm waits to ring again.
class SnoozeChip extends StatelessWidget {
  const SnoozeChip({super.key, required this.until, required this.now});
  final DateTime until;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = AnchorColors.of(context);
    return Chip(
      avatar: Icon(Icons.snooze, color: c.onState),
      label: Text('Snoozed ${formatCountdown(until.difference(now))}'),
      labelStyle: TextStyle(color: c.onState, fontWeight: FontWeight.w600),
      backgroundColor: c.warning,
      side: BorderSide.none,
    );
  }
}
