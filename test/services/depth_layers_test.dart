import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/services/map/tile_layer_spec.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activeTileLayers: base, depth overlay, seamarks (bottom to top)', () {
    const s = AppSettings(baseMap: BaseMap.bathymetry, depthLayer: DepthLayer.gebco);
    expect(activeTileLayers(s).map((l) => l.key), ['emodnet_base', 'gebco_depth', 'seamarks']);
    expect(
      activeTileLayers(const AppSettings(
        baseMap: BaseMap.none,
        depthLayer: DepthLayer.emodnet,
        seamarks: false,
      )).map((l) => l.key),
      ['emodnet_depth'],
    );
  });

  test('EMODnet base layer is WMTS web_mercator z/x/y', () {
    expect(
      TileLayerSpec.emodnetBase.url(12, 2234, 1502),
      'https://tiles.emodnet-bathymetry.eu/2020/baselayer/web_mercator/12/2234/1502.png',
    );
    expect(TileLayerSpec.emodnetBase.maxNativeZoom, 15);
  });

  test('WMS overlay URLs match flutter_map WMSTileLayerOptions', () {
    for (final spec in [TileLayerSpec.emodnetDepth, TileLayerSpec.gebcoDepth]) {
      final w = spec.wms!;
      final fm = WMSTileLayerOptions(baseUrl: w.baseUrl, layers: w.layers);
      const c = TileCoordinates(8938, 6010, 14);
      final ours = Uri.parse(spec.url(c.z, c.x, c.y)).queryParameters;
      final theirs = Uri.parse(fm.getUrl(c, 256, false)).queryParameters;
      expect(ours.keys.toSet(), theirs.keys.toSet());
      for (final k in ours.keys.where((k) => k != 'bbox')) {
        expect(ours[k], theirs[k], reason: k);
      }
      final a = ours['bbox']!.split(',').map(double.parse).toList();
      final b = theirs['bbox']!.split(',').map(double.parse).toList();
      for (var i = 0; i < 4; i++) {
        expect(a[i], closeTo(b[i], 0.01));
      }
      expect(spec.transparent, isTrue);
    }
  });
}
