import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../services/location/simulated_location_source.dart';

String simScenarioLabel(SimScenario s) => switch (s) {
      SimScenario.swing => 'Swinging',
      SimScenario.drag => 'Dragging',
      SimScenario.glitches => 'GPS glitches',
      SimScenario.poorGps => 'Poor GPS',
      SimScenario.gpsLoss => 'GPS lost',
    };

/// Chip showing the simulator scenario; tap to pick another one.
/// Shown only when the GPS simulator is enabled in the settings.
class SimulatorChip extends ConsumerStatefulWidget {
  const SimulatorChip({super.key});

  @override
  ConsumerState<SimulatorChip> createState() => _SimulatorChipState();
}

class _SimulatorChipState extends ConsumerState<SimulatorChip> {
  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(settingsProvider.select((s) => s.useSimulator));
    if (!enabled) return const SizedBox.shrink();
    final sim = ref.watch(simulatorProvider);
    return PopupMenuButton<SimScenario>(
      tooltip: 'Simulator scenario',
      initialValue: sim.scenario,
      onSelected: (s) => setState(() => sim.scenario = s),
      itemBuilder: (_) => [
        for (final s in SimScenario.values)
          CheckedPopupMenuItem(
            value: s,
            checked: s == sim.scenario,
            child: Text(simScenarioLabel(s)),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.science_outlined),
        label: Text('Simulator: ${simScenarioLabel(sim.scenario)}'),
      ),
    );
  }
}
