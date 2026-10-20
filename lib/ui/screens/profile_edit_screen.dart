import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../domain/models.dart';
import 'profiles_screen.dart';

/// Edits a custom profile; shows built-ins read-only with a "Duplicate" button.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key, required this.profile});
  final AlarmProfile profile;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late AlarmProfile _p = widget.profile;
  late final _name = TextEditingController(text: widget.profile.name);

  bool get _readOnly => _p.builtIn;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _set(AlarmProfile Function(AlarmProfile) f) {
    if (_readOnly) return;
    setState(() => _p = f(_p));
  }

  void _save() {
    final name = _name.text.trim();
    ref.read(profilesProvider.notifier).upsert(_p.copyWith(name: name.isEmpty ? 'Custom' : name));
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${_p.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    if (ref.read(settingsProvider).activeProfileId == _p.id) {
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(activeProfileId: AlarmProfile.overnightId));
    }
    ref.read(profilesProvider.notifier).remove(_p.id);
    if (mounted) Navigator.pop(context);
  }

  void _duplicate() {
    final copy = ProfilesScreen.duplicate(_p);
    ref.read(profilesProvider.notifier).upsert(copy);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ProfileEditScreen(profile: copy)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider.select((s) => s.distanceUnit));
    final active = ref.watch(settingsProvider.select((s) => s.activeProfileId)) == _p.id;
    final ro = _readOnly;
    return Scaffold(
      appBar: AppBar(
        title: Text(ro ? _p.name : 'Edit profile'),
        actions: [
          if (!ro)
            IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (ro)
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Built-in profile'),
                subtitle: const Text('Duplicate it to change the values.'),
                trailing: FilledButton(onPressed: _duplicate, child: const Text('Duplicate')),
              ),
            )
          else
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use this profile'),
            value: active,
            onChanged: (v) {
              if (v) {
                ref.read(settingsProvider.notifier).update((s) => s.copyWith(activeProfileId: _p.id));
              }
            },
          ),
          _SliderField(
            label: 'Warning ring',
            valueText: '${(_p.warningRatio * 100).round()} % of the alarm radius',
            value: _p.warningRatio,
            min: 0.5,
            max: 0.95,
            divisions: 9,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(warningRatio: v)),
          ),
          _SliderField(
            label: 'Alarm delay',
            help: 'How long the boat must stay outside before it alarms.',
            valueText: '${_p.alarmDelaySec} s',
            value: _p.alarmDelaySec.toDouble(),
            min: 0,
            max: 60,
            divisions: 12,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(alarmDelaySec: v.round())),
          ),
          _SliderField(
            label: 'Position averaging',
            valueText: _p.averagingSec == 0 ? 'off' : '${_p.averagingSec} s',
            value: _p.averagingSec.toDouble(),
            min: 0,
            max: 30,
            divisions: 6,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(averagingSec: v.round())),
          ),
          _SliderField(
            label: 'GPS lost alarm after',
            valueText: '${_p.gpsLostSec} s',
            value: _p.gpsLostSec.toDouble(),
            min: 15,
            max: 300,
            divisions: 19,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(gpsLostSec: v.round())),
          ),
          _SliderField(
            label: 'Poor GPS warning when accuracy worse than',
            valueText: formatDistance(_p.poorAccuracyM, unit),
            value: _p.poorAccuracyM,
            min: 10,
            max: 100,
            divisions: 18,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(poorAccuracyM: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Learn swing'),
            subtitle: const Text(
                'Widen the radius (never shrink, max +50 %) in the first 15 minutes.'),
            value: _p.learnSwing,
            onChanged: ro ? null : (v) => _set((p) => p.copyWith(learnSwing: v)),
          ),
          _SliderField(
            label: 'Low battery warning',
            valueText: '${_p.lowBatteryWarnPct} %',
            value: _p.lowBatteryWarnPct.toDouble(),
            min: 5,
            max: 50,
            divisions: 9,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(
                  lowBatteryWarnPct: v.round(),
                  lowBatteryAlarmPct:
                      p.lowBatteryAlarmPct > v.round() ? v.round() : p.lowBatteryAlarmPct,
                )),
          ),
          _SliderField(
            label: 'Low battery alarm',
            valueText: '${_p.lowBatteryAlarmPct} %',
            value: _p.lowBatteryAlarmPct.toDouble(),
            min: 5,
            max: 50,
            divisions: 9,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(
                  lowBatteryAlarmPct: v.round(),
                  lowBatteryWarnPct:
                      p.lowBatteryWarnPct < v.round() ? v.round() : p.lowBatteryWarnPct,
                )),
          ),
          _SliderField(
            label: 'Snooze after silencing',
            valueText: formatDuration(Duration(seconds: _p.snoozeSec)),
            value: _p.snoozeSec.toDouble(),
            min: 30,
            max: 600,
            divisions: 19,
            enabled: !ro,
            onChanged: (v) => _set((p) => p.copyWith(snoozeSec: v.round())),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibrate'),
            value: _p.vibrate,
            onChanged: ro ? null : (v) => _set((p) => p.copyWith(vibrate: v)),
          ),
          if (!ro) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save profile')),
          ],
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.onChanged,
    this.help,
  });

  final String label;
  final String? help;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            Text(valueText, style: theme.textTheme.titleMedium),
          ]),
          if (help != null) Text(help!, style: theme.textTheme.bodySmall),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueText,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
