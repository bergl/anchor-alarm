import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/offline_area_controller.dart';
import '../../app/providers.dart';
import '../../app/watch_controller.dart';

/// Settings → Map: automatic offline chart around the anchor and
/// "Download chart around me now". Shows nothing where downloads are not
/// supported (web).
class OfflineAreaSettingsTiles extends ConsumerWidget {
  const OfflineAreaSettingsTiles({super.key});

  /// Used for the size estimate before there is a GPS fix.
  static const _fallbackCentre = LatLng(45, 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineDownloadSupportedProvider)) return const SizedBox.shrink();
    final auto = ref.watch(settingsProvider.select((s) => s.autoOfflineMap));
    ref.watch(offlineLayersProvider); // re-estimate when the layers change
    final state = ref.watch(offlineAreaProvider);
    final ctrl = ref.read(offlineAreaProvider.notifier);
    final w = ref.read(watchControllerProvider);
    final centre = w.session?.anchor ?? w.fix?.position ?? _fallbackCentre;
    final mb = (ctrl.estimateBytes(centre) / (1024 * 1024)).ceil().clamp(1, 1 << 20);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SwitchListTile(
        secondary: const Icon(Icons.offline_pin_outlined),
        title: const Text('Save chart around anchor automatically'),
        subtitle: Text('Downloads ~$mb MB when a watch starts; needs internet'),
        value: auto,
        onChanged: (v) => ref
            .read(settingsProvider.notifier)
            .update((x) => x.copyWith(autoOfflineMap: v)),
      ),
      ListTile(
        leading: const Icon(Icons.download_for_offline_outlined),
        title: const Text('Download chart around me now'),
        subtitle: Text(switch (state) {
          OfflineAreaDownloading(:final percent) => 'Saving… $percent % — tap to stop',
          OfflineAreaDone(when: final at) => 'Last saved ${_time(context, at)}',
          _ => 'About 15 km around the boat, more detail close by',
        }),
        onTap: () async {
          if (state is OfflineAreaDownloading) {
            ctrl.cancel();
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          ctrl.downloadAroundMe();
          final now = ref.read(offlineAreaProvider);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(now is OfflineAreaSkipped
                  ? now.reason
                  : 'Saving chart for offline use…'),
            ));
        },
      ),
    ]);
  }

  static String _time(BuildContext context, DateTime t) {
    final local = t.toLocal();
    return TimeOfDay.fromDateTime(local).format(context);
  }
}
