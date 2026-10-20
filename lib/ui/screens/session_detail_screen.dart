import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../domain/models.dart';
import '../map/session_map.dart';
import '../ui_providers.dart';

/// One finished session: map with track, facts, alerts and editable notes.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.session});
  final AnchorSession session;

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  late AnchorSession _session = widget.session;
  late final _name = TextEditingController(text: widget.session.name ?? '');
  late final _notes = TextEditingController(text: widget.session.notes);
  bool _dirty = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = _session.copyWith(notes: _notes.text.trim(), name: _name.text.trim());
    await ref.read(sessionRepositoryProvider).save(updated);
    ref.invalidate(historyProvider);
    if (!mounted) return;
    setState(() {
      _session = updated;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this anchor watch?'),
        content: const Text('The log entry and its track will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(sessionRepositoryProvider).delete(_session.id);
    ref.invalidate(historyProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final unit = ref.watch(settingsProvider.select((x) => x.distanceUnit));
    final depthUnit = ref.watch(settingsProvider.select((x) => x.depthUnit));
    final track = ref.watch(trackProvider(s.id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text((s.name?.isNotEmpty ?? false) ? s.name! : formatDateTime(s.startedAt)),
        actions: [
          IconButton(
            tooltip: 'Delete',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SizedBox(
            height: 280,
            child: track.when(
              data: (t) => SessionMap(session: s, track: t),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => SessionMap(session: s, track: const []),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Fact('Started', formatDateTime(s.startedAt)),
                if (s.endedAt != null) _Fact('Ended', formatDateTime(s.endedAt!)),
                _Fact('Duration', formatDuration(s.duration(s.endedAt ?? s.startedAt))),
                _Fact('Alarm radius', formatDistance(s.radiusM, unit)),
                _Fact('Max distance', formatDistance(s.maxDistanceM, unit)),
                if (s.rodeM != null) _Fact('Rode', formatDistance(s.rodeM, unit)),
                if (s.depthM != null) _Fact('Depth', formatDistance(s.depthM, depthUnit)),
                _Fact('Profile', s.profile.name),
                _Fact('Anchor', formatLatLon(s.anchor.latitude, s.anchor.longitude)),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Alerts', style: theme.textTheme.titleMedium),
          ),
          if (s.alerts.isEmpty)
            const ListTile(title: Text('No alerts — a quiet night.')),
          for (final a in s.alerts)
            ListTile(
              dense: true,
              leading: Icon(
                a.reason.isAlarm ? Icons.notifications_active : Icons.warning_amber,
                color: a.reason.isAlarm ? theme.colorScheme.error : null,
              ),
              title: Text(alertTitle(a.reason)),
              subtitle: Text([
                formatTime(a.time),
                if (a.distanceM != null) formatDistance(a.distanceM, unit),
                if (a.acknowledgedAt != null) 'silenced ${formatTime(a.acknowledgedAt!)}',
              ].join(' · ')),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Place name'),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notes (holding, bottom, wind…)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _dirty ? _save : null,
                  child: const Text('Save notes'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
