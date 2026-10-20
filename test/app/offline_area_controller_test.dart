import 'dart:async';

import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/app/offline_area_controller.dart';
import 'package:anchor_alarm/app/providers.dart';
import 'package:anchor_alarm/app/watch_controller.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/services/map/offline_area_history.dart';
import 'package:anchor_alarm/services/map/tile_cache.dart';
import 'package:anchor_alarm/ui/widgets/offline_chart_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Records downloads; [gate] holds each download until completed or cancelled.
class FakeDownloader implements TileDownloader {
  FakeDownloader({this.failPerCall = 0});

  final calls = <({int minZoom, int maxZoom, List<String> layers})>[];
  final tokens = <TileDownloadCancelToken?>[];
  Completer<void>? gate;
  int failPerCall;
  bool throws = false;

  @override
  TileCache get cache => throw UnimplementedError();

  @override
  int get maxTiles => maxDownloadTiles;

  @override
  int estimateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required List<TileLayerSpec> layers,
  }) =>
      countTilesInArea(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, layers: layers);

  @override
  Future<int> downloadArea({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required List<TileLayerSpec> layers,
    void Function(int done, int total)? onProgress,
    TileDownloadCancelToken? cancel,
  }) async {
    calls.add((minZoom: minZoom, maxZoom: maxZoom, layers: [for (final l in layers) l.key]));
    tokens.add(cancel);
    if (throws) throw StateError('disk full');
    final total = estimateTileCount(
        bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, layers: layers);
    onProgress?.call(0, total);
    while (gate != null && !gate!.isCompleted && !(cancel?.isCancelled ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (cancel?.isCancelled ?? false) return 0;
    onProgress?.call(total, total);
    return failPerCall;
  }

  @override
  Future<int> cacheSizeBytes() async => 0;

  @override
  Future<void> clearCache() async {}
}

class TestWatchController extends WatchController {
  @override
  WatchViewState build() => const WatchViewState();
  void set(WatchViewState s) => state = s;
}

const anchor = LatLng(43.508, 16.44);

AnchorSession session(String id, {LatLng at = anchor}) => AnchorSession(
      id: id,
      anchor: at,
      radiusM: 40,
      initialRadiusM: 40,
      profile: AlarmProfile.builtIns[1],
      startedAt: DateTime.utc(2026, 10, 20),
    );

class Env {
  Env({
    AppSettings settings = const AppSettings(),
    bool supported = true,
    List<OfflineAreaRecord>? history,
  }) : history = MemoryOfflineAreaHistory(history) {
    container = ProviderContainer(overrides: [
      initialSettingsProvider.overrideWithValue(settings),
      watchControllerProvider.overrideWith(TestWatchController.new),
      tileDownloaderProvider.overrideWithValue(downloader),
      offlineAreaHistoryProvider.overrideWithValue(this.history),
      offlineDownloadSupportedProvider.overrideWithValue(supported),
    ]);
    // Keep the controller alive and listening, as the map screen does.
    container.listen(offlineAreaProvider, (_, s) => states.add(s), fireImmediately: true);
  }

  late final ProviderContainer container;
  final downloader = FakeDownloader();
  final MemoryOfflineAreaHistory history;
  final states = <OfflineAreaState>[];

  OfflineAreaState get state => container.read(offlineAreaProvider);
  TestWatchController get watch =>
      container.read(watchControllerProvider.notifier) as TestWatchController;

  void startWatch([String id = 's1', LatLng at = anchor]) =>
      watch.set(WatchViewState(session: session(id, at: at)));
  void stopWatch() => watch.set(const WatchViewState());

  Future<void> settle() async {
    for (var i = 0; i < 200 && state is OfflineAreaDownloading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  void dispose() => container.dispose();
}

void main() {
  test('watch start downloads the plan once (three bands, active layers)', () async {
    final env = Env();
    addTearDown(env.dispose);
    env.startWatch();
    await env.settle();

    expect(env.downloader.calls.map((c) => (c.minZoom, c.maxZoom)),
        [(10, 12), (13, 15), (16, 17)]);
    expect(env.downloader.calls.first.layers, ['osm', 'seamarks']);
    final done = env.state as OfflineAreaDone;
    expect(done.failed, 0);
    expect(done.auto, isTrue);
    expect(env.states.whereType<OfflineAreaDownloading>(), isNotEmpty);
    expect(env.history.records.single.centre, anchor);

    // Further watch updates (fixes, radius changes) do not trigger again.
    env.watch.set(WatchViewState(session: session('s1').copyWith(radiusM: 50)));
    await env.settle();
    expect(env.downloader.calls, hasLength(3));
  });

  test('setting off → no download', () async {
    final env = Env(settings: const AppSettings(autoOfflineMap: false));
    addTearDown(env.dispose);
    env.startWatch();
    await env.settle();
    expect(env.downloader.calls, isEmpty);
    expect(env.state, isA<OfflineAreaIdle>());
  });

  test('unsupported platform (web) → skipped, nothing downloaded', () async {
    final env = Env(supported: false);
    addTearDown(env.dispose);
    env.startWatch();
    await env.settle();
    expect(env.downloader.calls, isEmpty);
    expect((env.state as OfflineAreaSkipped).kind, OfflineSkipReason.unsupported);
    expect(await env.container.read(offlineAreaProvider.notifier).downloadAroundMe(),
        isA<OfflineAreaSkipped>());
    expect(env.downloader.calls, isEmpty);
  });

  test('no layers → skipped', () async {
    final env = Env(settings: const AppSettings(baseMap: BaseMap.none, seamarks: false));
    addTearDown(env.dispose);
    env.startWatch();
    await env.settle();
    expect((env.state as OfflineAreaSkipped).kind, OfflineSkipReason.noLayers);
  });

  test('stopWatch cancels the running download', () async {
    final env = Env();
    addTearDown(env.dispose);
    env.downloader.gate = Completer<void>();
    env.startWatch();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(env.state, isA<OfflineAreaDownloading>());

    env.stopWatch();
    await env.settle();
    expect(env.downloader.tokens.single!.isCancelled, isTrue);
    expect(env.downloader.calls, hasLength(1), reason: 'remaining bands not started');
    expect(env.state, isA<OfflineAreaIdle>());
    expect(env.history.records, isEmpty);
  });

  test('cancel() from the chip stops the download', () async {
    final env = Env();
    addTearDown(env.dispose);
    env.downloader.gate = Completer<void>();
    env.startWatch();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    env.container.read(offlineAreaProvider.notifier).cancel();
    await env.settle();
    expect(env.state, isA<OfflineAreaIdle>());
  });

  test('same area completed recently → skipped; old or other layers → downloaded', () async {
    final now = DateTime.now();
    const nearby = LatLng(43.5098, 16.44); // ~200 m north
    final env = Env(history: [
      OfflineAreaRecord(
          centre: nearby,
          completedAt: now.subtract(const Duration(days: 2)),
          layerKeys: const ['osm', 'seamarks']),
    ]);
    addTearDown(env.dispose);
    env.startWatch();
    await env.settle();
    expect(env.downloader.calls, isEmpty);
    expect((env.state as OfflineAreaSkipped).kind, OfflineSkipReason.recent);

    // Restarting the watch at the same spot after a completed download: skipped too.
    env.stopWatch();
    env.startWatch('s2', const LatLng(44.0, 15.0));
    await env.settle();
    expect(env.downloader.calls, hasLength(3));
    env.stopWatch();
    env.startWatch('s3', const LatLng(44.001, 15.0));
    await env.settle();
    expect(env.downloader.calls, hasLength(3));
    expect((env.state as OfflineAreaSkipped).kind, OfflineSkipReason.recent);
  });

  test('old record or a new layer → downloaded again', () async {
    final now = DateTime.now();
    final env = Env(
      settings: const AppSettings(depthLayer: DepthLayer.emodnet),
      history: [
        OfflineAreaRecord(
            centre: anchor,
            completedAt: now.subtract(const Duration(days: 1)),
            layerKeys: const ['osm', 'seamarks']),
        OfflineAreaRecord(
            centre: anchor,
            completedAt: now.subtract(const Duration(days: 8)),
            layerKeys: const ['osm', 'emodnet_depth', 'seamarks']),
      ],
    );
    addTearDown(env.dispose);
    env.startWatch();
    await env.settle();
    expect(env.downloader.calls, hasLength(3));
    expect(env.state, isA<OfflineAreaDone>());
    // The 8-day-old record is pruned.
    expect(env.history.records, hasLength(2));
  });

  test('download around me uses the boat position and ignores the history', () async {
    final env = Env(history: [
      OfflineAreaRecord(
          centre: anchor, completedAt: DateTime.now(), layerKeys: const ['osm', 'seamarks']),
    ]);
    addTearDown(env.dispose);
    final ctrl = env.container.read(offlineAreaProvider.notifier);
    expect(await ctrl.downloadAroundMe(), isA<OfflineAreaSkipped>(), reason: 'no fix yet');

    env.watch.set(WatchViewState(
        fix: PositionFix(position: anchor, accuracyM: 5, time: DateTime.now())));
    final f = ctrl.downloadAroundMe();
    expect(env.state, isA<OfflineAreaDownloading>());
    final r = await f as OfflineAreaDone;
    expect(r.auto, isFalse);
    expect(env.downloader.calls, hasLength(3));
  });

  test('download errors never escape: state is error', () async {
    final env = Env();
    addTearDown(env.dispose);
    env.downloader.failPerCall = 1 << 20;
    env.startWatch();
    await env.settle();
    expect(env.state, isA<OfflineAreaError>());
    expect(env.history.records, isEmpty);
  });

  test('a throwing downloader → error state, nothing escapes', () async {
    final env = Env();
    addTearDown(env.dispose);
    env.downloader.throws = true;
    env.startWatch();
    await env.settle();
    expect((env.state as OfflineAreaError).message, contains('disk full'));
  });

  testWidgets('map chip shows progress, tap stops; hidden when unsupported', (tester) async {
    for (final supported in [true, false]) {
      final env = Env(supported: supported);
      env.downloader.gate = Completer<void>();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: env.container,
        child: const MaterialApp(home: Scaffold(body: Center(child: OfflineChartChip()))),
      ));
      await tester.runAsync(() async {
        env.startWatch();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      if (!supported) {
        expect(find.byType(ActionChip), findsNothing);
        expect(env.downloader.calls, isEmpty);
        env.dispose();
        continue;
      }
      expect(find.text('Saving chart for offline · 0 %'), findsOneWidget);
      await tester.tap(find.byType(ActionChip));
      await tester.runAsync(env.settle);
      await tester.pump();
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Saving the chart for offline use stopped'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      env.dispose();
    }
  });
}
