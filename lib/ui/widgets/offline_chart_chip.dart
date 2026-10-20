import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/offline_area_controller.dart';
import '../ui_providers.dart';

/// Map overlay chip while the chart is saved for offline use
/// ("Saving chart for offline · 37 %", tap to cancel), and a brief SnackBar
/// when it is done. Shows nothing on the web.
///
/// Also keeps [offlineAreaProvider] alive, so the automatic download starts
/// with the watch.
class OfflineChartChip extends ConsumerWidget {
  const OfflineChartChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineAreaProvider);
    final supported = ref.watch(offlineDownloadSupportedProvider);

    ref.listen<OfflineAreaState>(offlineAreaProvider, (prev, next) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      void say(String text) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
      }

      if (prev is OfflineAreaDownloading && next is! OfflineAreaDownloading) {
        ref.invalidate(tileCacheSizeProvider);
      }
      switch (next) {
        case OfflineAreaDone(:final failed):
          say(failed == 0
              ? 'Chart saved for offline use'
              : 'Chart saved for offline use ($failed tiles missing)');
        case OfflineAreaError():
          if (prev is OfflineAreaDownloading) {
            say('Could not save the chart for offline use — no internet?');
          }
        case OfflineAreaIdle():
          if (prev is OfflineAreaDownloading) say('Saving the chart for offline use stopped');
        default:
      }
    });

    if (!supported || state is! OfflineAreaDownloading) return const SizedBox.shrink();
    return Tooltip(
      message: 'Tap to stop',
      child: ActionChip(
        avatar: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: state.total == 0 ? null : state.fraction,
          ),
        ),
        label: Text('Saving chart for offline · ${state.percent} %'),
        onPressed: () => ref.read(offlineAreaProvider.notifier).cancel(),
      ),
    );
  }
}
