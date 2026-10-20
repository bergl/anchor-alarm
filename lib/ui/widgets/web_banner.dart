import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/watch_controller.dart';

/// Web only, while watching: browsers stop location in background tabs.
class WebWatchBanner extends ConsumerWidget {
  const WebWatchBanner({super.key, this.force = false});

  /// Show regardless of platform (tests).
  final bool force;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watching = ref.watch(watchControllerProvider.select((s) => s.watching));
    if (!(kIsWeb || force) || !watching) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(Icons.tab, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Keep this tab open and the screen on — browsers stop location '
              'in the background.',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ]),
      ),
    );
  }
}
