import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/app_settings.dart';
import '../../../app/format.dart';
import '../../../app/providers.dart';
import '../../../app/watch_controller.dart';
import '../../../domain/geo.dart';
import '../../../domain/scope.dart';
import '../../ui_providers.dart';
import '../../widgets/number_input.dart';
import '../../widgets/permission_notice.dart';
import '../../widgets/profile_selector.dart';
import '../../widgets/weather_line.dart';
import 'drop_anchor_model.dart';
import 'drop_anchor_providers.dart';

/// "Drop anchor" form shown over the lower part of the map, so the anchor
/// and rings can be previewed (and placed by long-press/drag) live.
class DropAnchorPanel extends ConsumerStatefulWidget {
  const DropAnchorPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<DropAnchorPanel> createState() => _DropAnchorPanelState();
}

/// Delay after the anchor position changes before its charted depth is
/// looked up.
const chartedDepthDebounce = Duration(milliseconds: 600);

/// The anchor must move this far before the charted depth is looked up again
/// (GPS jitter, and the settled anchor shifting when the depth changes).
const _chartedDepthMoveM = 25.0;

class _DropAnchorPanelState extends ConsumerState<DropAnchorPanel> {
  ProviderSubscription<AnchorDraft?>? _sync;
  ProviderSubscription<LatLng?>? _anchorSub;
  Timer? _depthTimer;
  LatLng? _depthLookedUpAt;
  int _depthSeq = 0;

  @override
  void initState() {
    super.initState();
    // Mirror the form into the controller's draft for the live map preview.
    _sync = ref.listenManual<AnchorDraft?>(draftPreviewProvider, (_, d) => _push(d));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _push(ref.read(draftPreviewProvider));
    });
    // Charted depth at the anchor, debounced.
    _anchorSub = ref.listenManual<LatLng?>(
      draftPreviewProvider.select((d) => d?.anchor),
      (_, a) => _scheduleDepthLookup(a),
      fireImmediately: true,
    );
  }

  void _scheduleDepthLookup(LatLng? anchor) {
    if (anchor == null) return;
    final last = _depthLookedUpAt;
    if (last != null && distanceM(last, anchor) < _chartedDepthMoveM) return;
    _depthTimer?.cancel();
    _depthTimer = Timer(chartedDepthDebounce, () => _lookupDepth(anchor));
  }

  Future<void> _lookupDepth(LatLng anchor) async {
    final seq = ++_depthSeq;
    _depthLookedUpAt = anchor;
    final sample = await ref.read(depthServiceProvider).depthAt(anchor);
    if (!mounted || seq != _depthSeq) return;
    ref.read(dropAnchorFormProvider.notifier).applyChartedDepth(sample);
  }

  void _push(AnchorDraft? d) {
    final c = ref.read(watchControllerProvider.notifier);
    d == null ? c.clearDraft() : c.setDraft(d);
  }

  @override
  void dispose() {
    _sync?.close();
    _anchorSub?.close();
    _depthTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final draft = ref.read(draftPreviewProvider);
    if (draft == null) return;
    final form = ref.read(dropAnchorFormProvider);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          boat: s.boat.copyWith(lastRodeM: form.rodeM, lastDepthM: form.depthM),
        ));
    _sync?.close();
    _sync = null;
    widget.onClose();
    await ref.read(watchControllerProvider.notifier).startWatch(
          anchor: draft.anchor,
          radiusM: draft.radiusM,
          profile: ref.read(activeProfileProvider),
          rodeM: form.rodeM,
          depthM: form.depthM,
        );
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(dropAnchorFormProvider);
    final formCtrl = ref.read(dropAnchorFormProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(activeProfileProvider);
    final draft = ref.watch(draftPreviewProvider);
    final hasFix = ref.watch(watchControllerProvider.select((s) => s.fix != null));
    final theme = Theme.of(context);
    final dU = settings.distanceUnit;
    final depthU = settings.depthUnit;
    final radius = form.radius(settings.boat);
    final suggested = form.suggestedRadius(settings.boat);

    return Card(
      elevation: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(children: [
              const Icon(Icons.anchor),
              const SizedBox(width: 8),
              Expanded(child: Text('Drop anchor', style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip: 'Cancel',
                iconSize: 28,
                onPressed: () {
                  ref.read(watchControllerProvider.notifier).clearDraft();
                  widget.onClose();
                },
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                const PermissionNotice(),
                Text('Where is the anchor?', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                _MethodTile(
                  method: AnchorMethod.settled,
                  selected: form.method,
                  icon: Icons.sailing,
                  title: 'Boat has settled',
                  subtitle: 'Anchor is ahead of the bow',
                  onTap: () => formCtrl.update((f) => f.copyWith(method: AnchorMethod.settled)),
                ),
                _MethodTile(
                  method: AnchorMethod.here,
                  selected: form.method,
                  icon: Icons.my_location,
                  title: 'Anchor is here',
                  subtitle: 'At the boat\'s position now',
                  onTap: () => formCtrl.update((f) => f.copyWith(method: AnchorMethod.here)),
                ),
                _MethodTile(
                  method: AnchorMethod.map,
                  selected: form.method,
                  icon: Icons.touch_app,
                  title: 'Place on map',
                  subtitle: 'Long-press the map, or drag the anchor',
                  onTap: () => formCtrl.update((f) => f.copyWith(
                        method: AnchorMethod.map,
                        mapAnchor: f.mapAnchor ?? draft?.anchor,
                      )),
                ),
                if (form.method == AnchorMethod.settled) const _BowDirection(),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: NumberStepper(
                      label: 'Rode out',
                      value: fromMetres(form.rodeM, dU).roundToDouble(),
                      suffix: unitSuffix(dU),
                      step: dU == DistanceUnit.feet ? 10 : 5,
                      max: dU == DistanceUnit.feet ? 1000 : 300,
                      onChanged: (v) => formCtrl.update((f) => f.copyWith(rodeM: toMetres(v, dU))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NumberStepper(
                      label: 'Depth',
                      value: fromMetres(form.depthM, depthU).roundToDouble(),
                      suffix: unitSuffix(depthU),
                      step: 1,
                      max: depthU == DistanceUnit.feet ? 300 : 100,
                      onChanged: (v) => formCtrl.setDepth(toMetres(v, depthU)),
                    ),
                  ),
                ]),
                if (form.chartedDepth case final charted?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      charted.depthM < minPrefillDepthM
                          // Grid cell on the coastline: the value is not usable.
                          ? 'Charted depth < ${formatDistance(minPrefillDepthM, depthU)} '
                              '(${charted.source}, coastline cell) — check your sounder'
                          : 'Charted depth ≈ ${formatDistance(charted.depthM, depthU, decimals: 1)} '
                              '(${charted.source}) — check your sounder',
                      key: const ValueKey('chartedDepthCaption'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                _ScopeHint(rodeM: form.rodeM, depthM: form.depthM, unit: dU),
                const WeatherOutlookHint(),
                const SizedBox(height: 12),
                Text('Alarm profile', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                ProfileSelector(
                  selectedId: profile.id,
                  onSelected: (p) => ref
                      .read(settingsProvider.notifier)
                      .update((s) => s.copyWith(activeProfileId: p.id)),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Text(
                      'Alarm radius ${formatDistance(radius, dU)}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (form.radiusOverrideM != null)
                    TextButton(
                      onPressed: () => formCtrl.update((f) => f.copyWith(clearRadiusOverride: true)),
                      child: Text('Use suggested ${formatDistance(suggested, dU)}'),
                    ),
                ]),
                Slider(
                  value: radius,
                  min: minRadiusM,
                  max: maxRadiusM,
                  label: formatDistance(radius, dU),
                  onChanged: (v) => formCtrl.update((f) => f.copyWith(radiusOverrideM: v.roundToDouble())),
                ),
                Text(
                  form.radiusOverrideM == null
                      ? 'Suggested from rode, depth, boat length and GPS margin. '
                          'Warning at ${formatDistance(radius * profile.warningRatio, dU)} '
                          '(${(profile.warningRatio * 100).round()} %).'
                      : 'Warning at ${formatDistance(radius * profile.warningRatio, dU)} '
                          '(${(profile.warningRatio * 100).round()} %).',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              onPressed: draft == null ? null : _start,
              icon: const Icon(Icons.play_arrow, size: 28),
              label: Text(draft == null
                  ? (hasFix ? 'Place the anchor on the map' : 'Waiting for GPS…')
                  : 'Start anchor watch'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AnchorMethod method;
  final AnchorMethod selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSel = method == selected;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        selected: isSel,
        selectedTileColor: scheme.secondaryContainer,
        selectedColor: scheme.onSecondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isSel ? scheme.secondary : scheme.outlineVariant),
        ),
        leading: Icon(icon, size: 28),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(isSel ? Icons.radio_button_checked : Icons.radio_button_off),
        onTap: onTap,
      ),
    );
  }
}

/// Live compass value, or a dial to set the bow direction by hand.
class _BowDirection extends ConsumerWidget {
  const _BowDirection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compass = ref.watch(headingProvider).value;
    final form = ref.watch(dropAnchorFormProvider);
    final theme = Theme.of(context);
    if (compass != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Transform.rotate(
            angle: compass * 3.141592653589793 / 180,
            child: const Icon(Icons.navigation, size: 28),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Bow points ${formatBearing(compass)} (compass)',
                style: theme.textTheme.titleMedium),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No compass — set the bow direction: ${formatBearing(form.manualBowDeg)}',
              style: theme.textTheme.bodyMedium),
          Slider(
            value: form.manualBowDeg,
            min: 0,
            max: 355,
            divisions: 71,
            label: formatBearing(form.manualBowDeg),
            onChanged: (v) => ref
                .read(dropAnchorFormProvider.notifier)
                .update((f) => f.copyWith(manualBowDeg: v)),
          ),
        ],
      ),
    );
  }
}

/// Warns about short scope and says how much rode gives 3:1 and 5:1.
class _ScopeHint extends StatelessWidget {
  const _ScopeHint({required this.rodeM, required this.depthM, required this.unit});

  final double rodeM;
  final double depthM;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final a = scopeAdvice(rodeM: rodeM, depthM: depthM);
    final theme = Theme.of(context);
    final ratio = '${a.ratio.toStringAsFixed(1)}:1';
    final (icon, color, text) = switch (a.rating) {
      ScopeRating.tooShort => (
          Icons.error_outline,
          theme.colorScheme.error,
          'Rode is shorter than the depth. Let out at least '
              '${formatDistance(a.rodeFor5M, unit)} (5:1).',
        ),
      ScopeRating.short => (
          Icons.warning_amber_rounded,
          theme.colorScheme.error,
          'Short scope ($ratio) — likely to drag. Let out '
              '${formatDistance(a.rodeFor3M, unit)} for 3:1, '
              '${formatDistance(a.rodeFor5M, unit)} for 5:1.',
        ),
      ScopeRating.fair => (
          Icons.info_outline,
          theme.colorScheme.onSurfaceVariant,
          'Scope $ratio — fine for all-chain in settled weather; '
              '${formatDistance(a.rodeFor5M, unit)} for 5:1 if the wind rises.',
        ),
      ScopeRating.good => (
          Icons.check_circle_outline,
          theme.colorScheme.onSurfaceVariant,
          'Scope $ratio.',
        ),
    };
    return Padding(
      key: const ValueKey('scopeHint'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ),
      ]),
    );
  }
}
