import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/watch_controller.dart';
import '../../services/location/location_source.dart';

/// Opens the system settings for the app or for location services.
/// Overridable in tests.
final openSettingsProvider = Provider<Future<void> Function({bool location})>(
  (ref) => ({bool location = false}) async {
    try {
      if (location) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {
      // Not available on this platform.
    }
  },
);

/// Explains a location permission problem and offers to fix it.
/// Renders nothing when permission is fine (or not yet asked).
class PermissionNotice extends ConsumerWidget {
  const PermissionNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(watchControllerProvider);
    final p = s.permission;
    if (p == null || p == LocationPermissionResult.always) {
      return const SizedBox.shrink();
    }
    // On the web "while in use" is all there is.
    if (p == LocationPermissionResult.whileInUse && (kIsWeb || !s.watching)) {
      return const SizedBox.shrink();
    }
    final (title, body, openLocation) = switch (p) {
      LocationPermissionResult.serviceDisabled => (
          'Location is switched off',
          'Turn on location services so the app can see where the boat is.',
          true,
        ),
      LocationPermissionResult.deniedForever => (
          'Location permission blocked',
          'Open the app settings and allow location — "Allow all the time" / '
              '"Always" so the watch keeps running with the screen off.',
          false,
        ),
      LocationPermissionResult.whileInUse => (
          'Allow location "Always"',
          'With "While using the app" the anchor watch may stop when the phone '
              'is locked. Choose "Allow all the time" / "Always" in the settings.',
          false,
        ),
      _ => (
          'Location permission needed',
          'The anchor watch needs your position. Please allow location — '
              '"Always" for watching in the background.',
          false,
        ),
    };
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(watchControllerProvider.notifier);
    final open = ref.read(openSettingsProvider);
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.location_off, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: scheme.onErrorContainer)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (p == LocationPermissionResult.denied)
                FilledButton(
                  onPressed: () =>
                      controller.requestPermission(background: s.watching),
                  child: const Text('Allow location'),
                ),
              OutlinedButton(
                onPressed: () => open(location: openLocation),
                child: Text(openLocation ? 'Location settings' : 'Open settings'),
              ),
              TextButton(
                onPressed: () =>
                    controller.requestPermission(background: s.watching),
                child: const Text('Check again'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
