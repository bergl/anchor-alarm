import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/services/map/offline_area.dart';
import 'package:anchor_alarm/services/map/tile_layer_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // An anchorage in Croatia, one in Norway (tiles are narrower up north).
  const adriatic = LatLng(43.508, 16.44);
  const norway = LatLng(68.4, 15.0);
  const planner = OfflineAreaPlanner();
  final defaultLayers = activeTileLayers(const AppSettings());
  final withDepth = activeTileLayers(const AppSettings(depthLayer: DepthLayer.emodnet));

  int perZoom(OfflineAreaPlan p, String band) =>
      p.requests.firstWhere((r) => r.band.name == band).tiles;

  test('default layers are base map and seamarks', () {
    expect(defaultLayers.map((l) => l.key), ['osm', 'seamarks']);
  });

  test('default plan: three bands, modest tile count', () {
    final p = planner.plan(adriatic, [TileLayerSpec.osm]);
    expect(p.requests.map((r) => r.band.name), ['overview', 'approach', 'anchorage']);
    expect(p.requests.map((r) => (r.minZoom, r.maxZoom)), [(10, 12), (13, 15), (16, 17)]);
    // Bands keep their full radius.
    expect(p.requests.map((r) => r.band.radiusM), [15000, 3000, 600]);
    // ~15 km at z10–12: a handful of tiles per zoom.
    expect(perZoom(p, 'overview'), inInclusiveRange(15, 60));
    expect(perZoom(p, 'approach'), inInclusiveRange(40, 120));
    expect(perZoom(p, 'anchorage'), inInclusiveRange(30, 100));
    expect(p.totalTiles, inInclusiveRange(100, 300));
    // ignore: avoid_print
    print('osm only: $p');
  });

  test('osm + seamarks and with a depth overlay stay under the limit untouched', () {
    final a = planner.plan(adriatic, defaultLayers);
    final b = planner.plan(adriatic, withDepth);
    final osm = planner.plan(adriatic, [TileLayerSpec.osm]).totalTiles;
    expect(a.totalTiles, 2 * osm);
    // The EMODnet overlay stops at z14: nothing to fetch at z16–17.
    expect(b.requests.last.layers.map((l) => l.key), isNot(contains('emodnet_depth')));
    expect(b.totalTiles, greaterThan(a.totalTiles));
    expect(b.totalTiles, lessThanOrEqualTo(maxDownloadTiles));
    expect(b.requests.map((r) => r.band.radiusM), [15000, 3000, 600]);
    // Rough size: a few MB.
    expect(a.estimatedBytes, inInclusiveRange(1 << 20, 20 << 20));
    // ignore: avoid_print
    print('osm+seamarks: $a, ~${a.estimatedBytes >> 20} MB\n'
        'osm+emodnet+seamarks: $b, ~${b.estimatedBytes >> 20} MB\n'
        'norway osm+seamarks: ${planner.plan(norway, defaultLayers)}');
  });

  test('no layers → empty plan', () {
    expect(planner.plan(adriatic, const []).isEmpty, isTrue);
  });

  test('many layers: outer bands shrink first, limit never exceeded', () {
    final many = [
      for (var i = 0; i < 20; i++)
        TileLayerSpec(key: 'l$i', urlTemplate: 'https://x/{z}/{x}/{y}', attribution: ''),
    ];
    final p = planner.plan(adriatic, many);
    expect(p.totalTiles, lessThanOrEqualTo(maxDownloadTiles));
    final radii = {for (final r in p.requests) r.band.name: r.band.radiusM};
    expect(radii['anchorage'], 600, reason: 'inner band untouched');
    expect(radii['overview'] ?? 0, lessThan(15000));
    // ignore: avoid_print
    print('20 layers: $p');
  });

  test('tight budgets: plans never exceed the limit', () {
    for (final limit in [3000, 1000, 400, 100, 30, 5, 0]) {
      for (final layers in [defaultLayers, withDepth, [TileLayerSpec.osm]]) {
        for (final c in [adriatic, norway, const LatLng(0, 0), const LatLng(-33.9, 151.2)]) {
          final p = OfflineAreaPlanner(maxTiles: limit).plan(c, layers);
          expect(p.totalTiles, lessThanOrEqualTo(limit), reason: '$limit $c $p');
        }
      }
    }
  });

  test('a small budget keeps the anchorage detail, outer bands shrink', () {
    final full = planner.plan(adriatic, defaultLayers);
    final anchorage = full.requests.last.tiles;
    final p = OfflineAreaPlanner(maxTiles: anchorage).plan(adriatic, defaultLayers);
    expect(p.totalTiles, lessThanOrEqualTo(anchorage));
    expect(p.requests.last.band.name, 'anchorage');
    expect(p.requests.last.band.maxZoom, 17);
    for (final r in p.requests.take(p.requests.length - 1)) {
      expect(r.band.radiusM, r.band.minRadiusM, reason: 'outer bands shrunk to the minimum');
    }
  });

  test('bounds around the centre have the requested size', () {
    final b = boundsAround(adriatic, 1000);
    expect(b.north - b.south, closeTo(2000 / 111320, 1e-6));
    expect(b.center.latitude, closeTo(adriatic.latitude, 1e-5));
  });
}
