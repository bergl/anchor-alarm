import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/remote_controllers.dart';
import '../../app/watch_controller.dart';
import '../../services/remote/firebase_config.dart';
import 'monitor_screen.dart';
import 'share_watch_sheet.dart';

/// App menu entries: "Share watch" (while watching) and "Monitor a boat".
/// In builds without Firebase they are shown disabled with an explanation.
class RemoteMenuItems extends ConsumerWidget {
  const RemoteMenuItems({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(remoteServicesProvider) != null;
    final watching = ref.watch(watchControllerProvider.select((s) => s.watching));
    final sharing = ref.watch(shareControllerProvider.select((s) => s.sharing));
    final monitored = ref.watch(monitoredBoatsProvider).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (watching)
          ListTile(
            leading: Icon(sharing ? Icons.share_location : Icons.share_outlined),
            title: const Text('Share watch'),
            subtitle: Text(!configured
                ? remoteNotConfiguredMessage
                : sharing
                    ? 'Shared — tap for the link'
                    : 'Let someone ashore monitor the boat'),
            enabled: configured,
            onTap: () {
              final navContext = Navigator.of(context).context;
              Navigator.pop(context);
              showShareWatchSheet(navContext);
            },
          ),
        ListTile(
          leading: const Icon(Icons.visibility_outlined),
          title: const Text('Monitor a boat'),
          subtitle: Text(!configured
              ? remoteNotConfiguredMessage
              : monitored == 0
                  ? 'Watch another boat\'s anchor alarm'
                  : 'Monitoring $monitored ${monitored == 1 ? 'boat' : 'boats'}'),
          enabled: configured,
          onTap: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute<void>(builder: (_) => const MonitorBoatsScreen()));
          },
        ),
      ],
    );
  }
}
