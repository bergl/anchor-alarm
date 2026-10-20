import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../domain/models.dart';
import '../ui_providers.dart';
import 'session_detail_screen.dart';

/// Past anchor watches, newest first.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the history.\n$e')),
        data: (sessions) => sessions.isEmpty
            ? const _EmptyHistory()
            : ListView.separated(
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => SessionTile(session: sessions[i]),
              ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.anchor, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text(
              'No anchor watches yet.\nFinished watches will be listed here.',
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
}

class SessionTile extends ConsumerWidget {
  const SessionTile({super.key, required this.session});
  final AnchorSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(settingsProvider.select((s) => s.distanceUnit));
    final s = session;
    final alarms = s.alerts.where((a) => a.reason.isAlarm).length;
    final title = (s.name?.isNotEmpty ?? false) ? s.name! : formatDateTime(s.startedAt);
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: alarms > 0
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        foregroundColor: alarms > 0
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSecondaryContainer,
        child: Icon(alarms > 0 ? Icons.notifications_active : Icons.anchor),
      ),
      title: Text(title),
      subtitle: Text([
        if (s.name?.isNotEmpty ?? false) formatDateTime(s.startedAt),
        formatDuration(s.duration(s.endedAt ?? s.startedAt)),
        'max ${formatDistance(s.maxDistanceM, unit)} of ${formatDistance(s.radiusM, unit)}',
        alarms == 0 ? 'no alarms' : '$alarms alarm${alarms == 1 ? '' : 's'}',
      ].join(' · ')),
      isThreeLine: s.name?.isNotEmpty ?? false,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(session: s),
      )),
    );
  }
}
