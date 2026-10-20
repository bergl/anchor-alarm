import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/history_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/profiles_screen.dart';
import '../screens/settings_screen.dart';
import 'offline_download.dart';
import '../remote/remote_menu_items.dart';
import 'weather_sheet.dart';

/// Navigation drawer: History, Profiles, Settings, Intro.
class AppMenuDrawer extends ConsumerWidget {
  const AppMenuDrawer({super.key});

  void _open(BuildContext context, Widget page) {
    // Look the navigator up before closing the drawer: the drawer's context is
    // deactivated once it closes.
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute<void>(builder: (_) => page));
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
                Flexible(
                  child: Text('Anchor Alarm',
                      style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.air),
              title: const Text('Weather'),
              subtitle: const Text('Wind, gusts and waves for the next 24 h'),
              onTap: () {
                final navContext = Navigator.of(context).context;
                Navigator.pop(context);
                showWeatherSheet(navContext);
              },
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
            const RemoteMenuItems(),
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
