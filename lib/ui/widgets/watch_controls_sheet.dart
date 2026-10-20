import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../screens/drop_anchor/drop_anchor_model.dart';
import '../remote/share_watch_sheet.dart';
import 'anchorage_check.dart';
import 'profile_selector.dart';

Future<void> showWatchControlsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const WatchControlsSheet(),
    );

/// While watching: adjust the alarm radius and switch profile.
class WatchControlsSheet extends ConsumerStatefulWidget {
  const WatchControlsSheet({super.key});

  @override
  ConsumerState<WatchControlsSheet> createState() => _WatchControlsSheetState();
}

class _WatchControlsSheetState extends ConsumerState<WatchControlsSheet> {
  double? _radius;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(watchControllerProvider);
    final session = s.session;
    final unit = ref.watch(settingsProvider.select((x) => x.distanceUnit));
    final theme = Theme.of(context);
    if (session == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Not watching.'),
      );
    }
    final current = s.snapshot?.radiusM ?? session.radiusM;
    final radius = (_radius ?? current).clamp(minRadiusM, maxRadiusM).toDouble();
    final controller = ref.read(watchControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alarm radius ${formatDistance(radius, unit)}',
                style: theme.textTheme.titleLarge),
            Text(
              'Warning at ${formatDistance(radius * session.profile.warningRatio, unit)}',
              style: theme.textTheme.bodyMedium,
            ),
            Slider(
              value: radius,
              min: minRadiusM,
              max: maxRadiusM,
              label: formatDistance(radius, unit),
              onChanged: (v) => setState(() => _radius = v.roundToDouble()),
              onChangeEnd: (v) => controller.setRadius(v.roundToDouble()),
            ),
            const SizedBox(height: 16),
            Text('Alarm profile', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ProfileSelector(
              selectedId: session.profile.id,
              onSelected: (p) {
                controller.setProfile(p);
                ref
                    .read(settingsProvider.notifier)
                    .update((x) => x.copyWith(activeProfileId: p.id));
              },
            ),
            const SizedBox(height: 8),
            const ShareWatchTile(),
            ListTile(
              key: const ValueKey('checkAnchorage'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.travel_explore),
              title: const Text('Check this anchorage'),
              subtitle: const Text('Shelter, forecast exposure, nearby anchorages'),
              onTap: () {
                // The sheet's context goes away with it: open from the navigator's.
                final nav = Navigator.of(context);
                nav.pop();
                showAnchorageCheckSheet(nav.context);
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirms stopping the watch, with optional place name and notes.
Future<void> confirmStopWatch(BuildContext context, WidgetRef ref) async {
  final res = await showDialog<(String, String)>(
    context: context,
    builder: (_) => const _StopWatchDialog(),
  );
  if (res == null) return;
  final (name, notes) = res;
  await ref.read(watchControllerProvider.notifier).stopWatch(
        notes: notes.isEmpty ? null : notes,
        name: name.isEmpty ? null : name,
      );
}

class _StopWatchDialog extends StatefulWidget {
  const _StopWatchDialog();

  @override
  State<_StopWatchDialog> createState() => _StopWatchDialogState();
}

class _StopWatchDialogState extends State<_StopWatchDialog> {
  final _name = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Stop anchor watch?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The alarm will no longer watch the boat.'),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Place name (optional)'),
              ),
              TextField(
                controller: _notes,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep watching'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (_name.text.trim(), _notes.text.trim())),
            child: const Text('Stop watch'),
          ),
        ],
      );
}
