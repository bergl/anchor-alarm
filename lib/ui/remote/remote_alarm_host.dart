import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/remote_controllers.dart';
import '../../services/remote/push_service.dart';
import 'monitor_screen.dart';

/// Root navigator, so the alarm host (above the navigator) can open screens.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Wraps the whole app: keeps a live view of every monitored boat while the
/// app runs, shows the full-screen alarm when one of them rings, opens
/// `#join=` links (web) and shows foreground pushes for boats without a live
/// view. Does nothing when remote monitoring is not configured.
class RemoteAlarmHost extends ConsumerStatefulWidget {
  const RemoteAlarmHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<RemoteAlarmHost> createState() => _RemoteAlarmHostState();
}

class _RemoteAlarmHostState extends ConsumerState<RemoteAlarmHost> {
  StreamSubscription<RemotePush>? _pushSub;

  @override
  void initState() {
    super.initState();
    final services = ref.read(remoteServicesProvider);
    if (services == null) return;
    _pushSub = services.push.foreground.listen(_onPush);
    final link = ref.read(initialJoinLinkProvider);
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavigatorKey.currentState?.push(MaterialPageRoute<void>(
          builder: (_) => MonitorBoatsScreen(initialInput: link.url),
        ));
      });
    }
  }

  void _onPush(RemotePush p) {
    // Monitored boats have a live view that raises the alarm itself.
    final live = ref.read(monitoredBoatsProvider).any((b) => b.watchId == p.watchId);
    if (live) return;
    final title = p.title, body = p.body;
    if (title != null) {
      ref.read(notificationServiceProvider).showInfo(title: title, body: body ?? '');
    }
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boats = ref.watch(monitoredBoatsProvider);
    String? ringing;
    for (final b in boats) {
      // Watching keeps each boat's live view (and its alarm) running.
      if (ref.watch(monitorControllerProvider(b.watchId).select((m) => m.ringingHere))) {
        ringing ??= b.watchId;
      }
    }
    final id = ringing;
    return Stack(
      children: [
        widget.child,
        if (id != null)
          Positioned.fill(
            child: RemoteAlarmOverlay(
              watchId: id,
              onOpen: () {
                ref.read(monitorControllerProvider(id).notifier).silenceHere();
                rootNavigatorKey.currentState?.push(MaterialPageRoute<void>(
                  builder: (_) => MonitorScreen(watchId: id),
                ));
              },
            ),
          ),
      ],
    );
  }
}
