import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../../app/weather_controller.dart';
import '../../domain/geo.dart';
import '../../domain/weather.dart';
import '../../domain/weather_risk.dart';
import '../../services/weather/weather_service.dart';
import 'weather_line.dart';

/// Opens the weather bottom sheet (current conditions, next 24 h, alerts).
Future<void> showWeatherSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => WeatherSheet(scrollController: scroll),
      ),
    );

class WeatherSheet extends ConsumerStatefulWidget {
  const WeatherSheet({super.key, this.scrollController});
  final ScrollController? scrollController;

  @override
  ConsumerState<WeatherSheet> createState() => _WeatherSheetState();
}

class _WeatherSheetState extends ConsumerState<WeatherSheet> {
  @override
  void initState() {
    super.initState();
    // Not watching: fetch for the boat's position if needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(weatherControllerProvider.notifier).ensureFresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(weatherControllerProvider);
    final watch = ref.watch(watchControllerProvider);
    final theme = Theme.of(context);
    final now = clock.now();
    final f = w.forecast;
    final risk = w.risk;
    final here = watch.session?.anchor ?? watch.snapshot?.position ?? watch.fix?.position;
    final awayM = f == null || here == null ? null : distanceM(f.location, here);
    final unit = ref.watch(settingsProvider.select((s) => s.distanceUnit));

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(children: [
          Icon(Icons.air, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Weather', style: theme.textTheme.titleLarge)),
          if (w.loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                  dimension: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            )
          else
            IconButton(
              tooltip: 'Refresh forecast',
              onPressed: () => ref.read(weatherControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
            ),
        ]),
        if (f != null)
          Text(
            formatForecastAge(f.fetchedAt, now) +
                (watch.watching ? ' · for the anchor' : ''),
            key: const ValueKey('forecastAge'),
            style: theme.textTheme.bodySmall,
          ),
        if (awayM != null && awayM > WeatherController.maxDistanceM)
          Text('Forecast for a position ${formatDistance(awayM, unit)} away',
              style: theme.textTheme.bodySmall),
        if (w.error != null)
          _Notice(
            icon: Icons.cloud_off,
            text: f == null
                ? '${w.error}. No forecast yet — try again when online.'
                : 'Offline — showing the last forecast (${w.error}).',
          )
        else if (f != null && w.isStale(now))
          const _Notice(icon: Icons.history, text: 'This forecast is old — refresh when online.'),
        if (f == null && w.error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              here == null
                  ? 'Waiting for a GPS position to fetch the forecast.'
                  : w.loading
                      ? 'Fetching the forecast…'
                      : 'No forecast yet.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (risk != null) ...[
          const SizedBox(height: 12),
          _Current(risk: risk),
          if (risk.alerts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Alerts (next 24 h)', style: theme.textTheme.titleSmall),
            for (final a in risk.alerts) _AlertTile(alert: a),
          ] else ...[
            const SizedBox(height: 8),
            Text('No forecast alerts for the next 24 h.', style: theme.textTheme.bodyMedium),
          ],
          if (risk.hours.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Next 24 h', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: CustomPaint(
                key: const ValueKey('windChart'),
                painter: WindChartPainter(
                  hours: risk.hours,
                  gustWarnKn: ref.watch(settingsProvider.select((s) => s.gustWarnKn)),
                  windColor: theme.colorScheme.primary,
                  gustColor: theme.colorScheme.secondary,
                  warnColor: weatherAlertColor(context),
                  gridColor: theme.colorScheme.outlineVariant,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Row(children: [
              _Legend(color: theme.colorScheme.primary, label: 'wind'),
              const SizedBox(width: 12),
              _Legend(color: theme.colorScheme.secondary, label: 'gusts'),
              const SizedBox(width: 12),
              _Legend(color: weatherAlertColor(context), label: 'gust alert'),
            ]),
            const SizedBox(height: 8),
            _HourHeader(showWaves: f?.hasMarine ?? false),
            for (final h in risk.hours) _HourRow(hour: h, showWaves: f?.hasMarine ?? false),
          ],
        ],
        const SizedBox(height: 16),
        Text(WeatherService.attribution, style: theme.textTheme.bodySmall),
        Text('Forecasts can be wrong — keep a proper watch.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }
}

/// Arrow pointing where the wind blows TO (rotated by the from-direction + 180°).
class WindArrow extends StatelessWidget {
  const WindArrow({super.key, required this.fromDeg, this.size = 20, this.color});
  final double? fromDeg;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final d = fromDeg;
    if (d == null) return SizedBox.square(dimension: size);
    return Transform.rotate(
      angle: (d + 180) * math.pi / 180,
      child: Icon(Icons.navigation, size: size, color: color),
    );
  }
}

class _Current extends StatelessWidget {
  const _Current({required this.risk});
  final WeatherRisk risk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = risk.current;
    if (c == null) return const SizedBox.shrink();
    String n(double? v, String unit, [int dec = 0]) =>
        v == null ? '–' : '${v.toStringAsFixed(dec)} $unit';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          WindArrow(fromDeg: c.windDirDeg, size: 36, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Wind ${n(c.windKn, 'kn')}'
                '${c.windDirDeg == null ? '' : ' ${compassPoint(c.windDirDeg!)}'}',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                [
                  'gusts ${n(c.gustKn, 'kn')}',
                  if (c.pressureHpa != null) n(c.pressureHpa, 'hPa'),
                  if (c.waveHeightM != null) 'waves ${n(c.waveHeightM, 'm', 1)}',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              if (risk.maxGust case final g?)
                Text('Max gust ${g.value.round()} kn at ${formatTime(g.time.toLocal())}',
                    style: theme.textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final WeatherAlert alert;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.warning_amber_rounded, color: weatherAlertColor(context)),
        title: Text(weatherAlertTitle(alert.kind)),
        subtitle: Text(alert.message),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _HourHeader extends StatelessWidget {
  const _HourHeader({required this.showWaves});
  final bool showWaves;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.labelSmall;
    return Row(children: [
      SizedBox(width: 52, child: Text('Time', style: s)),
      const SizedBox(width: 28),
      Expanded(child: Text('Wind kn', style: s)),
      Expanded(child: Text('Gusts', style: s)),
      if (showWaves) Expanded(child: Text('Waves m', style: s)),
      Expanded(child: Text('hPa', style: s)),
    ]);
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({required this.hour, required this.showWaves});
  final HourlyWeather hour;
  final bool showWaves;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.textTheme.bodyMedium;
    String n(double? v, [int dec = 0]) => v == null ? '–' : v.toStringAsFixed(dec);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 52, child: Text(formatTime(hour.time.toLocal()), style: s)),
        SizedBox(
          width: 28,
          child: WindArrow(fromDeg: hour.windDirDeg, size: 18,
              color: theme.colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            '${n(hour.windKn)}'
            '${hour.windDirDeg == null ? '' : ' ${compassPoint(hour.windDirDeg!)}'}',
            style: s,
          ),
        ),
        Expanded(child: Text(n(hour.gustKn), style: s)),
        if (showWaves) Expanded(child: Text(n(hour.waveHeightM, 1), style: s)),
        Expanded(child: Text(n(hour.pressureHpa), style: s)),
      ]),
    );
  }
}

/// Bars of sustained wind and a gust line over the next hours, with the gust
/// alert threshold dashed. No chart library needed.
class WindChartPainter extends CustomPainter {
  WindChartPainter({
    required this.hours,
    required this.gustWarnKn,
    required this.windColor,
    required this.gustColor,
    required this.warnColor,
    required this.gridColor,
  });

  final List<HourlyWeather> hours;
  final double gustWarnKn;
  final Color windColor;
  final Color gustColor;
  final Color warnColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (hours.isEmpty || size.isEmpty) return;
    var maxV = gustWarnKn;
    for (final h in hours) {
      maxV = math.max(maxV, math.max(h.windKn ?? 0, h.gustKn ?? 0));
    }
    maxV *= 1.1;
    double y(double v) => size.height - v / maxV * size.height;
    final slot = size.width / hours.length;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), grid);

    final bar = Paint()..color = windColor.withValues(alpha: 0.7);
    for (var i = 0; i < hours.length; i++) {
      final w = hours[i].windKn;
      if (w == null) continue;
      canvas.drawRect(
          Rect.fromLTRB(i * slot + slot * 0.15, y(w), (i + 1) * slot - slot * 0.15, size.height),
          bar);
    }

    final gust = Paint()
      ..color = gustColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    var started = false;
    for (var i = 0; i < hours.length; i++) {
      final g = hours[i].gustKn;
      if (g == null) continue;
      final p = Offset((i + 0.5) * slot, y(g));
      started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
      started = true;
      if (g >= gustWarnKn) canvas.drawCircle(p, 3, Paint()..color = warnColor);
    }
    canvas.drawPath(path, gust);

    // Dashed threshold line.
    final warn = Paint()
      ..color = warnColor
      ..strokeWidth = 1.5;
    final ty = y(gustWarnKn);
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 4, size.width), ty), warn);
    }
  }

  @override
  bool shouldRepaint(WindChartPainter old) =>
      old.hours != hours ||
      old.gustWarnKn != gustWarnKn ||
      old.windColor != windColor ||
      old.gustColor != gustColor ||
      old.warnColor != warnColor;
}
