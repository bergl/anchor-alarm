import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/remote_controllers.dart';
import '../../services/remote/firebase_config.dart';

Future<void> showShareWatchSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ShareWatchSheet(),
    );

/// Entry in the watch controls sheet: "Share this watch".
class ShareWatchTile extends ConsumerWidget {
  const ShareWatchTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shareControllerProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(s.sharing ? Icons.share_location : Icons.share_outlined),
      title: const Text('Share this watch'),
      subtitle: Text(!s.configured
          ? remoteNotConfiguredMessage
          : s.sharing
              ? 'Shared — others can monitor this boat'
              : 'Let someone ashore monitor the boat'),
      enabled: s.configured,
      trailing: s.configured ? const Icon(Icons.chevron_right) : null,
      onTap: s.configured ? () => showShareWatchSheet(context) : null,
    );
  }
}

/// Opt-in sharing for the active watch: switch, boat name, QR code, link,
/// "Stop sharing".
class ShareWatchSheet extends ConsumerStatefulWidget {
  const ShareWatchSheet({super.key});

  @override
  ConsumerState<ShareWatchSheet> createState() => _ShareWatchSheetState();
}

class _ShareWatchSheetState extends ConsumerState<ShareWatchSheet> {
  late final TextEditingController _name =
      TextEditingController(text: ref.read(shareControllerProvider).boatName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: const Text(
            'The link stops working and everyone monitoring this boat is removed. '
            'Sharing again creates a new link.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop sharing')),
        ],
      ),
    );
    if (ok == true) await ref.read(shareControllerProvider.notifier).disable();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(shareControllerProvider);
    final controller = ref.read(shareControllerProvider.notifier);
    final theme = Theme.of(context);
    final link = s.sharing ? s.record!.link : null;

    Widget body;
    if (!s.configured) {
      body = const Text(remoteNotConfiguredMessage);
    } else if (s.sessionId == null) {
      body = const Text('Start an anchor watch first, then share it.');
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share this watch'),
            subtitle: const Text(
                'Uploads the anchor, alarm rings, boat position and alarm state '
                'every few seconds while the watch runs. Off by default.'),
            value: s.sharing,
            onChanged: s.busy
                ? null
                : (on) async {
                    if (on) {
                      await controller.setBoatName(_name.text);
                      await controller.enable();
                    } else {
                      await _confirmStop();
                    }
                  },
          ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Boat name',
              helperText: 'Shown to people monitoring',
            ),
            onSubmitted: controller.setBoatName,
            onTapOutside: (_) => controller.setBoatName(_name.text),
          ),
          if (s.busy) const LinearProgressIndicator(),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (link != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                // QR codes need dark-on-light to scan, also in the night theme.
                color: Colors.white,
                child: QrImageView(
                  data: link.url,
                  size: 200,
                  backgroundColor: Colors.white,
                  semanticsLabel: 'QR code of the share link',
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(link.url, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy link'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link.url));
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(const SnackBar(content: Text('Link copied')));
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Anyone with this link can see the boat\'s position and alarm state '
              'and gets its alarms on their phone (Anchor Alarm app → Monitor a boat, '
              'or the web app). Only share it with people you trust. '
              '"Stop sharing" makes the link useless.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('Stop sharing'),
              onPressed: _confirmStop,
            ),
          ],
        ],
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Remote monitoring', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      ),
    );
  }
}
