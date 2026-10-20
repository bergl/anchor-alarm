import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import 'profile_edit_screen.dart';

/// Built-in and custom alarm profiles.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  static AlarmProfile duplicate(AlarmProfile p) => p.copyWith(
        id: const Uuid().v4(),
        name: '${p.name} (custom)',
        builtIn: false,
      );

  void _edit(BuildContext context, AlarmProfile p) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ProfileEditScreen(profile: p)),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(settingsProvider.select((s) => s.activeProfileId));
    return Scaffold(
      appBar: AppBar(title: const Text('Alarm profiles')),
      body: ListView(
        children: [
          for (final p in profiles)
            ListTile(
              leading: Icon(p.builtIn ? Icons.lock_outline : Icons.person_outline),
              title: Text(p.name),
              subtitle: Text(_summary(p)),
              selected: p.id == activeId,
              trailing: p.builtIn
                  ? IconButton(
                      tooltip: 'Duplicate to edit',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        final copy = duplicate(p);
                        ref.read(profilesProvider.notifier).upsert(copy);
                        _edit(context, copy);
                      },
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => _edit(context, p),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Built-in profiles cannot be changed — duplicate one to make your own.',
            ),
          ),
        ],
      ),
    );
  }

  static String _summary(AlarmProfile p) =>
      'Warning at ${(p.warningRatio * 100).round()} % · delay ${p.alarmDelaySec} s · '
      'GPS lost ${p.gpsLostSec} s${p.learnSwing ? ' · learns swing' : ''}';
}
