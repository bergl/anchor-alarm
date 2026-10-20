import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/anchorage_assistant.dart';
import '../../app/app_settings.dart';
import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/watch_controller.dart';
import '../../domain/anchorage_assessment.dart';
import '../../domain/exposure.dart';
import '../../domain/geo.dart';
import '../../domain/scope.dart';
import '../../services/map/anchorage_service.dart';
import '../../services/map/depth_service.dart';
import '../theme/app_theme.dart';

/// Colours of the shelter ratings: green / amber / red by day, three
/// brightnesses of red at night.
Color shelterColor(BuildContext context, ShelterRating r) {
  final night = AnchorColors.of(context).night;
  return switch (r) {
    ShelterRating.sheltered => night ? const Color(0xFF5C1414) : const Color(0xFF2E7D32),
    ShelterRating.partly => night ? AppTheme.nightRed : const Color(0xFFF9A825),
    ShelterRating.exposed => night ? AppTheme.nightRedBright : const Color(0xFFD32F2F),
  };
}

/// Icon colour for an overall rating (null = not enough data).
Color ratingColor(BuildContext context, AnchorageRating? r) {
  final c = AnchorColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  if (c.night) {
    return switch (r) {
      AnchorageRating.poor => AppTheme.nightRedBright,
      AnchorageRating.caution => const Color(0xFFE57373),
      _ => scheme.onSurfaceVariant,
    };
  }
  return switch (r) {
    AnchorageRating.good => c.safe,
    AnchorageRating.caution => const Color(0xFFE08E00),
    AnchorageRating.poor => c.alarm,
    null => scheme.onSurfaceVariant,
  };
}

IconData ratingIcon(AnchorageRating? r) => switch (r) {
      AnchorageRating.good => Icons.check_circle_outline,
      AnchorageRating.caution => Icons.warning_amber_rounded,
      AnchorageRating.poor => Icons.error_outline,
      null => Icons.travel_explore,
    };

/// Opens the anchorage check for the watched anchor (from the adjust sheet).
Future<void> showAnchorageCheckSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Keep the map (rose, swing arc) visible above the sheet.
      barrierColor: Colors.black12,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scroll) => Consumer(builder: (context, ref, _) {
          final s = ref.watch(watchControllerProvider);
          final session = s.session;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              AnchorageCheckCard(
                point: session?.anchor ?? s.fix?.position,
                rodeM: session?.rodeM,
                depthM: session?.depthM,
                lookupDepth: true,
                collapsible: false,
              ),
            ],
          );
        }),
      ),
    );

/// "Anchorage check": one-line verdict that expands to shelter by sector,
/// the forecast exposure timeline, depth & scope, the user's own history
/// and nearby anchorages. Works with any of these missing.
class AnchorageCheckCard extends ConsumerStatefulWidget {
  const AnchorageCheckCard({
    super.key,
    required this.point,
    this.rodeM,
    this.depthM,
    this.chartedDepth,
    this.lookupDepth = false,
    this.collapsible = true,
  });

  /// Position to check (draft anchor or anchor); null while unknown.
  final LatLng? point;
  final double? rodeM;
  final double? depthM;

  /// Charted depth known by the caller (Drop anchor panel).
  final DepthSample? chartedDepth;

  /// Look the charted depth up (when the caller has none).
  final bool lookupDepth;

  /// False: always expanded (in the bottom sheet).
  final bool collapsible;

  @override
  ConsumerState<AnchorageCheckCard> createState() => _AnchorageCheckCardState();
}

/// Delay after the point moves before it is checked again.
const anchorageCheckDebounce = Duration(milliseconds: 700);

class _AnchorageCheckCardState extends ConsumerState<AnchorageCheckCard> {
  late bool _expanded = !widget.collapsible;
  Timer? _timer;
  late final AnchorageCheckController _ctrl = ref.read(anchorageCheckProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.setExpanded(_expanded);
      _check();
    });
  }

  @override
  void didUpdateWidget(AnchorageCheckCard old) {
    super.didUpdateWidget(old);
    final a = old.point, b = widget.point;
    if (b != null && (a == null || distanceM(a, b) >= 1)) {
      _timer?.cancel();
      _timer = Timer(anchorageCheckDebounce, _check);
    }
  }

  void _check() {
    final p = widget.point;
    if (p == null || !mounted) return;
    unawaited(_ctrl.check(p, lookupDepth: widget.lookupDepth));
  }

  @override
  void dispose() {
    _timer?.cancel();
    final c = _ctrl;
    // Not during the widget tree's teardown.
    Future.microtask(() => c.setExpanded(false));
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _ctrl.setExpanded(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final check = ref.watch(anchorageCheckProvider);
    final a = ref.watch(anchorageAssessmentProvider);
    final theme = Theme.of(context);
    final loading = check.maskLoading && check.exposure == null;
    final summary = widget.point == null
        ? 'Waiting for a position…'
        : loading
            ? 'Checking shelter…'
            : a?.summary ?? 'Checking…';
    final color = ratingColor(context, a?.rating);

    final header = InkWell(
      key: const ValueKey('anchorageCheckHeader'),
      borderRadius: BorderRadius.circular(12),
      onTap: widget.collapsible ? _toggle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          if (loading)
            const SizedBox.square(
                dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          else
            Icon(ratingIcon(a?.rating), color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Anchorage check', style: theme.textTheme.labelMedium),
              Text(
                summary,
                key: const ValueKey('anchorageCheckSummary'),
                maxLines: _expanded ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          if (widget.collapsible)
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                semanticLabel: _expanded ? 'Collapse anchorage check' : 'Expand anchorage check'),
        ]),
      ),
    );

    return Container(
      key: const ValueKey('anchorageCheck'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (_expanded && widget.point != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _Details(
              check: check,
              assessment: a,
              rodeM: widget.rodeM,
              depthM: widget.depthM,
              chartedDepth: widget.chartedDepth ?? check.chartedDepth,
            ),
          ),
      ]),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({
    required this.check,
    required this.assessment,
    required this.rodeM,
    required this.depthM,
    required this.chartedDepth,
  });

  final AnchorageCheckState check;
  final AnchorageAssessment? assessment;
  final double? rodeM;
  final double? depthM;
  final DepthSample? chartedDepth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final settings = ref.watch(settingsProvider);
    final a = assessment;
    final exp = check.exposure;
    final children = <Widget>[];

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(t, style: theme.textTheme.labelLarge),
        );

    // ---- Shelter
    children.add(heading('Shelter'));
    if (exp != null) {
      children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox.square(
          dimension: 76,
          child: CustomPaint(
            key: const ValueKey('exposureRoseIcon'),
            painter: ExposureRosePainter(
              exposure: exp,
              colors: {for (final r in ShelterRating.values) r: shelterColor(context, r)},
              textColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(exp.describe(), key: const ValueKey('shelterText'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              'Open water to land in 16 directions, up to 4 km '
              '(${exp.source} grid${exp.anchorOnLand ? '; the spot is on a coastline cell' : ''}). '
              'Sheltered < 500 m, exposed ≥ 2 km.',
              style: small,
            ),
          ]),
        ),
      ]));
    } else if (check.maskLoading) {
      children.add(Text('Analysing the coastline around the anchor…', style: small));
    } else {
      children.add(Row(children: [
        Expanded(
          child: Text(
            'No land data for this spot (offline, or no chart coverage) — shelter not analysed. '
            'Check the chart for open directions.',
            style: small,
          ),
        ),
        TextButton(
          onPressed: () => ref.read(anchorageCheckProvider.notifier).retry(),
          child: const Text('Retry'),
        ),
      ]));
    }

    // ---- Forecast
    children.add(heading('Forecast exposure, next 24 h'));
    if (a != null && a.hasForecast) {
      children.add(SizedBox(
        height: 64,
        child: CustomPaint(
          key: const ValueKey('exposureTimeline'),
          size: Size.infinite,
          painter: ExposureTimelinePainter(
            hours: a.hours,
            colors: {for (final r in ShelterRating.values) r: shelterColor(context, r)},
            neutral: theme.colorScheme.outline,
            textColor: theme.colorScheme.onSurfaceVariant,
            textStyle: small ?? const TextStyle(fontSize: 11),
          ),
        ),
      ));
      final windowLines = [
        for (final l in a.advice.skip(exp == null ? 0 : 1))
          if (!l.startsWith('Shelter could not')) l,
      ];
      for (final line in windowLines) {
        final bad = line.startsWith('Exposed');
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(bad ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 16, color: bad ? ratingColor(context, AnchorageRating.poor) : null),
            const SizedBox(width: 6),
            Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
          ]),
        ));
      }
    } else {
      children.add(Text(
        'No forecast yet — shelter only. Open Weather from the menu to fetch one.',
        style: small,
      ));
    }

    // ---- Depth & scope
    final depthLines = <String>[];
    final cd = chartedDepth;
    if (cd != null) {
      depthLines.add(cd.depthM < 1
          ? 'Charted depth < 1 m (${cd.source}, coastline cell)'
          : 'Charted depth ≈ ${formatDistance(cd.depthM, settings.depthUnit, decimals: 1)} '
              '(${cd.source}, ${cd.resolution})');
    }
    final r = rodeM, d = depthM;
    if (r != null && d != null) {
      final s = scopeAdvice(rodeM: r, depthM: d);
      final rating = switch (s.rating) {
        ScopeRating.tooShort => 'rode shorter than the depth',
        ScopeRating.short => 'short, likely to drag',
        ScopeRating.fair => 'fair',
        ScopeRating.good => 'good',
      };
      depthLines.add('Rode ${formatDistance(r, settings.distanceUnit)} in '
          '${formatDistance(d, settings.depthUnit)} → scope ${s.ratio.toStringAsFixed(1)}:1 ($rating); '
          '5:1 needs ${formatDistance(s.rodeFor5M, settings.distanceUnit)}');
    }
    if (depthLines.isNotEmpty) {
      children.add(heading('Depth & scope'));
      for (final l in depthLines) {
        children.add(Text(l, style: theme.textTheme.bodyMedium));
      }
    }

    // ---- History
    children.add(heading('Your log'));
    children.add(Text(
      check.history?.text ?? 'No earlier anchor watch within 500 m in your log.',
      key: const ValueKey('historyNote'),
      style: theme.textTheme.bodyMedium,
    ));

    // ---- Nearby
    children.add(heading('Nearby anchorages (OpenStreetMap)'));
    final list = check.anchorages;
    if (list != null && list.isNotEmpty) {
      children.add(Text(
        'Nearby: ${list.take(5).map((n) => '${n.label} (${_km(n.distanceM, settings.distanceUnit)})').join(', ')}',
        key: const ValueKey('nearbyText'),
        style: theme.textTheme.bodyMedium,
      ));
      children.add(SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Show on map'),
        value: check.showNearbyOnMap,
        onChanged: (v) => ref.read(anchorageCheckProvider.notifier).setShowNearbyOnMap(v),
      ));
    } else if (check.anchoragesLoading) {
      children.add(Text('Looking for anchorages nearby…', style: small));
    } else if (list != null) {
      children.add(Text('None mapped within 5 km.', style: small));
    } else {
      children.add(Text(
        'Unavailable — could not reach the OpenStreetMap (Overpass) service.',
        key: const ValueKey('nearbyUnavailable'),
        style: small,
      ));
    }

    children.add(Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Advisory only: based on a ~115 m depth grid (EMODnet / GEBCO) and a model '
        'forecast. Not for navigation — check the chart, the sky and your sounder.',
        style: small?.copyWith(fontStyle: FontStyle.italic),
      ),
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  static String _km(double m, DistanceUnit u) => u == DistanceUnit.feet
      ? '${(m / 1852).toStringAsFixed(1)} NM'
      : m < 1000
          ? '${(m / 10).round() * 10} m'
          : '${(m / 1000).toStringAsFixed(1)} km';
}

/// Small 16-sector rose: each wedge's length is the fetch (log-scaled),
/// its colour the rating.
class ExposureRosePainter extends CustomPainter {
  ExposureRosePainter({required this.exposure, required this.colors, required this.textColor});

  final ExposureProfile exposure;
  final Map<ShelterRating, Color> colors;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rMax = size.shortestSide / 2 - 8;
    final rMin = rMax * 0.22;
    final maxF = exposure.thresholds.maxFetchM;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = textColor.withValues(alpha: 0.35);
    canvas.drawCircle(c, rMax, ring);
    for (final s in exposure.sectors) {
      final f = (math.log(1 + s.fetchM / 100) / math.log(1 + maxF / 100)).clamp(0.0, 1.0);
      final r = rMin + (rMax - rMin) * f;
      final a0 = (s.bearingDeg - sectorWidthDeg / 2 - 90) * math.pi / 180;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: r), a0 + 0.03, sectorWidthDeg * math.pi / 180 - 0.06, false)
        ..close();
      canvas.drawPath(path, Paint()..color = colors[s.rating]!.withValues(alpha: 0.85));
    }
    final tp = TextPainter(
      text: TextSpan(text: 'N', style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(ExposureRosePainter old) =>
      old.exposure != exposure || old.colors != colors || old.textColor != textColor;
}

/// 24 hourly wind bars (height = wind, thin line = gusts) coloured by the
/// shelter of the direction the wind comes from; hour labels every 6 h.
class ExposureTimelinePainter extends CustomPainter {
  ExposureTimelinePainter({
    required this.hours,
    required this.colors,
    required this.neutral,
    required this.textColor,
    required this.textStyle,
  });

  final List<HourExposure> hours;
  final Map<ShelterRating, Color> colors;
  final Color neutral;
  final Color textColor;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (hours.isEmpty) return;
    const labelH = 14.0;
    final h = size.height - labelH;
    final n = hours.length;
    final w = size.width / n;
    final maxKn = math.max(
        20.0, hours.map((x) => math.max(x.windKn ?? 0, x.gustKn ?? 0)).fold(0.0, math.max));
    double y(double kn) => h - h * (kn / maxKn).clamp(0.0, 1.0);
    // 12 kn reference line.
    final ref = Paint()
      ..color = textColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(12)), Offset(size.width, y(12)), ref);
    final style = textStyle.copyWith(color: textColor, fontSize: 10);
    for (var i = 0; i < n; i++) {
      final x = hours[i];
      final col = x.rating == null ? neutral : colors[x.rating]!;
      final kn = x.windKn ?? 0;
      final left = i * w + w * 0.12;
      final right = (i + 1) * w - w * 0.12;
      final emphasise = x.risk != HourRisk.none;
      canvas.drawRect(
        Rect.fromLTRB(left, y(kn), right, h),
        Paint()..color = col.withValues(alpha: emphasise ? 1 : 0.55),
      );
      final g = x.gustKn;
      if (g != null && g > kn) {
        canvas.drawLine(Offset((left + right) / 2, y(g)), Offset((left + right) / 2, y(kn)),
            Paint()
              ..color = col
              ..strokeWidth = 1.5);
      }
      final local = x.time.toLocal();
      if (local.hour % 6 == 0) {
        final tp = TextPainter(
          text: TextSpan(text: local.hour.toString().padLeft(2, '0'), style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final tx = (i * w).clamp(0.0, size.width - tp.width);
        tp.paint(canvas, Offset(tx, h + 2));
      }
    }
    final tp = TextPainter(
      text: TextSpan(text: '${maxKn.round()} kn', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width, 0));
  }

  @override
  bool shouldRepaint(ExposureTimelinePainter old) =>
      old.hours != hours || old.colors != colors || old.neutral != neutral;
}

/// Label for a [NearbyAnchorage] kind (map tooltips).
String anchorageKindLabel(AnchorageKind k) => switch (k) {
      AnchorageKind.anchorage => 'Anchorage',
      AnchorageKind.anchorBerth => 'Anchor berth',
      AnchorageKind.marina => 'Marina',
    };
