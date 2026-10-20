import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Plays the alarm for a few seconds so the user can check the volume.
Future<void> runTestAlarm(BuildContext context, WidgetRef ref) async {
  final alarm = ref.read(alarmOutputProvider);
  final profile = ref.read(activeProfileProvider);
  await alarm.startAlarm(sound: profile.sound, vibrate: profile.vibrate);
  if (!context.mounted) {
    await alarm.stopAlarm();
    return;
  }
  final auto = Timer(const Duration(seconds: 10), () {
    if (context.mounted) Navigator.of(context, rootNavigator: true).maybePop();
  });
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.volume_up, size: 40),
      title: const Text('Testing the alarm'),
      content: const Text(
        'Is it loud enough to wake you? If not, turn up the alarm/media volume '
        'and check that Do Not Disturb lets the app through.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Stop'),
        ),
      ],
    ),
  );
  auto.cancel();
  await alarm.stopAlarm();
}
