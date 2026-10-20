import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_settings.dart';
import '../app/providers.dart';
import '../app/watch_controller.dart';
import 'remote/remote_alarm_host.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'ui_providers.dart';

class AnchorAlarmApp extends ConsumerWidget {
  const AnchorAlarmApp({super.key, this.restoreOnStart = true});

  /// Restore an interrupted watch when the map screen opens.
  final bool restoreOnStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePref = ref.watch(settingsProvider.select((s) => s.theme));
    final onboarded = ref.watch(settingsProvider.select((s) => s.onboardingDone));

    // Day theme for "day"; night (red) for "night"; system follows the platform:
    // light → day, dark → night.
    final (light, dark, mode) = switch (themePref) {
      ThemePref.day => (AppTheme.day(), AppTheme.day(), ThemeMode.light),
      ThemePref.night => (AppTheme.night(), AppTheme.night(), ThemeMode.dark),
      ThemePref.system => (AppTheme.day(), AppTheme.night(), ThemeMode.system),
    };

    return MaterialApp(
      title: 'Anchor Alarm',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      navigatorKey: rootNavigatorKey,
      // A `#join=...` share link is not a route: the navigator falls back to
      // home and RemoteAlarmHost opens the link.
      builder: (context, child) =>
          _ScreenWake(child: RemoteAlarmHost(child: child ?? const SizedBox())),
      home: onboarded
          ? MapScreen(restoreOnStart: restoreOnStart)
          : const OnboardingScreen(),
    );
  }
}

/// Keeps the screen on while watching when the setting asks for it.
class _ScreenWake extends ConsumerStatefulWidget {
  const _ScreenWake({required this.child});
  final Widget child;

  @override
  ConsumerState<_ScreenWake> createState() => _ScreenWakeState();
}

class _ScreenWakeState extends ConsumerState<_ScreenWake> {
  bool? _on;

  void _apply(bool on) {
    if (_on == on) return;
    _on = on;
    ref.read(screenWakeProvider)(on);
  }

  @override
  Widget build(BuildContext context) {
    final watching = ref.watch(watchControllerProvider.select((s) => s.watching));
    final keepOn = ref.watch(settingsProvider.select((s) => s.keepScreenOn));
    final want = watching && keepOn;
    if (want != (_on ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _apply(want);
      });
    }
    return widget.child;
  }
}
