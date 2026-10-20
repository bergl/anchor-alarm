import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';

/// Chips to pick an alarm profile (built-ins and custom).
class ProfileSelector extends ConsumerWidget {
  const ProfileSelector({super.key, required this.selectedId, required this.onSelected});

  final String selectedId;
  final ValueChanged<AlarmProfile> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in profiles)
          ChoiceChip(
            label: Text(p.name),
            selected: p.id == selectedId,
            onSelected: (_) => onSelected(p),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
      ],
    );
  }
}
