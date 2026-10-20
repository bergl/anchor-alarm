import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../widgets/test_alarm.dart';

/// Short first-launch intro: how it works, permissions, test the alarm.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  /// Opened again from the menu: finishing just closes it.
  final bool replay;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.replay) {
      Navigator.pop(context);
    } else {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _count - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [_WelcomePage(), _PermissionsPage(), _ReadyPage()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  for (var i = 0; i < _count; i++)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: last
                        ? _finish
                        : () => _pages.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                    child: Text(last ? 'Start' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        Icon(icon, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ]),
      );
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) => const _Page(
        icon: Icons.anchor,
        title: 'Sleep while the phone keeps watch',
        children: [
          _Bullet(Icons.place, 'Drop anchor, tell the app how much rode is out, '
              'and it draws a swing circle around the anchor.'),
          _Bullet(Icons.notifications_active, 'If the boat leaves the circle, '
              'loses GPS or the battery runs low, a loud alarm sounds.'),
          _Bullet(Icons.visibility, 'It is an aid — not a replacement for good '
              'seamanship and a proper anchor watch.'),
        ],
      );
}

class _PermissionsPage extends ConsumerWidget {
  const _PermissionsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Page(
        icon: Icons.my_location,
        title: 'Location "Always" and notifications',
        children: [
          const _Bullet(Icons.lock_clock, 'Allow location "Always" / "Allow all '
              'the time" so the watch keeps running with the screen off.'),
          const _Bullet(Icons.notifications, 'Allow notifications so the alarm '
              'can reach you on the lock screen.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref
                .read(watchControllerProvider.notifier)
                .requestPermission(background: true),
            icon: const Icon(Icons.my_location),
            label: const Text('Allow location'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => ref.read(notificationServiceProvider).requestPermission(),
            icon: const Icon(Icons.notifications),
            label: const Text('Allow notifications'),
          ),
        ],
      );
}

class _ReadyPage extends ConsumerWidget {
  const _ReadyPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Page(
        icon: Icons.battery_charging_full,
        title: 'Before you sleep',
        children: [
          const _Bullet(Icons.power, 'Keep the phone on a charger — GPS all night '
              'uses a lot of battery.'),
          const _Bullet(Icons.volume_up, 'Turn the volume up and test the alarm, '
              'so you know it will wake you.'),
          const _Bullet(Icons.dark_mode, 'Use the night theme (Settings) to keep '
              'your night vision.'),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => runTestAlarm(context, ref),
            icon: const Icon(Icons.volume_up),
            label: const Text('Test alarm'),
          ),
        ],
      );
}
