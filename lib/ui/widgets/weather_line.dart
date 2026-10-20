import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/weather_controller.dart';
import '../../domain/weather_risk.dart';
import '../theme/app_theme.dart';
import 'weather_sheet.dart';

/// Colour for weather alert icons: amber by day, bright red at night.
Color weatherAlertColor(BuildContext context) {
  final c = AnchorColors.of(context);
  return c.night ? AppTheme.nightRedBright : c.warning;
}

/// One line of weather in the watching status: current wind, gusts and the
/// highest gust ahead; amber icon when a forecast alert is active. Tap opens
/// the weather sheet. Also refreshes the forecast when the app is resumed.
class WeatherLine extends ConsumerStatefulWidget {
  const WeatherLine({super.key});

  @override
  ConsumerState<WeatherLine> createState() => _WeatherLineState();
}

class _WeatherLineState extends ConsumerState<WeatherLine> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(weatherControllerProvider.notifier).onAppResumed(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(weatherControllerProvider);
    final theme = Theme.of(context);
    final now = clock.now();
    final risk = w.risk;
    final summary = risk == null ? null : weatherSummary(risk);
    final String text;
    if (summary != null) {
      text = w.isStale(now)
          ? '$summary · ${formatAge(w.forecast!.age(now)).replaceAll(' ago', ' old')}'
          : summary;
    } else if (w.loading) {
      text = 'Weather: loading…';
    } else if (w.error != null) {
      text = 'Weather unavailable';
    } else {
      text = 'Weather forecast';
    }
    final alert = w.hasAlerts;
    return InkWell(
      key: const ValueKey('weatherLine'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showWeatherSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(
            alert ? Icons.warning_amber_rounded : Icons.air,
            key: ValueKey(alert ? 'weatherAlertIcon' : 'weatherIcon'),
            size: 20,
            color: alert ? weatherAlertColor(context) : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// Small outlook line for the Drop anchor panel, e.g.
/// "Next 12 h: wind veers NW→NE, gusts to 24 kn". Fetches a forecast for the
/// boat if there is none (or it is old); shows nothing without data.
class WeatherOutlookHint extends ConsumerStatefulWidget {
  const WeatherOutlookHint({super.key});

  @override
  ConsumerState<WeatherOutlookHint> createState() => _WeatherOutlookHintState();
}

class _WeatherOutlookHintState extends ConsumerState<WeatherOutlookHint> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(weatherControllerProvider.notifier)
            .ensureFresh(maxAge: WeatherController.refreshEvery);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(weatherControllerProvider);
    final f = w.forecast;
    final text = f == null ? null : anchoringOutlook(f, clock.now());
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return InkWell(
      key: const ValueKey('weatherOutlook'),
      onTap: () => showWeatherSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(
            w.hasAlerts ? Icons.warning_amber_rounded : Icons.air,
            size: 16,
            color: w.hasAlerts
                ? weatherAlertColor(context)
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ]),
      ),
    );
  }
}
