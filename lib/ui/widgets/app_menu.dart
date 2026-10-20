import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/history_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/profiles_screen.dart';
import '../screens/settings_screen.dart';
import 'offline_download.dart';

/// Navigation drawer: History, Profiles, Settings, Intro.
class AppMenuDrawer extends ConsumerWidget {
  const AppMenuDrawer({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(children: [
                Icon(Icons.anchor, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 12),
                Text('Anchor Alarm', style: theme.textTheme.titleLarge),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('History'),
              onTap: () => _open(context, const HistoryScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Alarm profiles'),
              onTap: () => _open(context, const ProfilesScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => _open(context, const SettingsScreen()),
            ),
            if (offlineDownloadSupported)
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Download this map area'),
                subtitle: const Text('For use without internet'),
                onTap: () {
                  // The drawer's context goes away when it closes; use the
                  // navigator's, which outlives it.
                  final navContext = Navigator.of(context).context;
                  Navigator.pop(context);
                  runOfflineDownload(navContext, ref);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('How it works'),
              onTap: () => _open(context, const OnboardingScreen(replay: true)),
            ),
          ],
        ),
      ),
    );
  }
}
