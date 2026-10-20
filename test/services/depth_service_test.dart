import 'dart:async';

import 'package:anchor_alarm/services/map/depth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

// Response bodies recorded from the real servers (2026-10-20) with the same
// requests DepthService sends.

const emodnetWater = r'''{"type":"FeatureCollection","features":[{"type":"Feature","id":"","geometry":null,"properties":{"Depth":-9.890625}}],"totalFeatures":"unknown","numberReturned":1,"timeStamp":"2026-10-20T15:09:36.523Z","crs":null}''';

const emodnetLand = r'''{"type":"FeatureCollection","features":[{"type":"Feature","id":"","geometry":null,"properties":{"Depth":256.1600646972656}}],"totalFeatures":"unknown","numberReturned":1,"timeStamp":"2026-10-20T15:09:37.613Z","crs":null}''';

const emodnetNoData = r'''{"type":"FeatureCollection","features":[{"type":"Feature","id":"","geometry":null,"properties":{"Depth":0}}],"totalFeatures":"unknown","numberReturned":1,"timeStamp":"2026-10-20T15:09:38.429Z","crs":null}''';

const emodnetError = r'''<?xml version="1.0" encoding="UTF-8" standalone="no"?><!DOCTYPE ServiceExceptionReport SYSTEM "http://ows.emodnet-bathymetry.eu/schemas/wms/1.1.1/WMS_exception_1_1_1.dtd"> <ServiceExceptionReport version="1.1.1" >   <ServiceException code="LayerNotDefined" locator="layers">
      Could not find layer emodnet:nope
</ServiceException></ServiceExceptionReport>''';

const emodnet502 = r'''<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>nginx/1.30.0</center>
</body>
</html>
''';

const gebcoWater = r'''GetFeatureInfo results:

Layer 'GEBCO_LATEST_2'
  Feature 0: 
    x = '-40.102083'
    y = '40.102083'
    value_list = '-4648'
''';

const gebcoLand = r'''GetFeatureInfo results:

Layer 'GEBCO_LATEST_2'
  Feature 0: 
    x = '16.602083'
    y = '43.16875'
    value_list = '218'
''';

const gebcoHvar = r'''GetFeatureInfo results:

Layer 'GEBCO_LATEST_2'
  Feature 0: 
    x = '16.397917'
    y = '43.152083'
    value_list = '-39'
''';

const gebcoNoResult = r'''GetFeatureInfo results:

  Search returned no results.
''';

/// Routes requests to EMODnet / GEBCO handlers and records the URLs.
MockClient _client({
  required FutureOr<http.Response> Function() emodnet,
  required FutureOr<http.Response> Function() gebco,
  List<Uri>? calls,
}) =>
    MockClient((req) async {
      calls?.add(req.url);
      if (req.url.host == 'ows.emodnet-bathymetry.eu') return emodnet();
      if (req.url.host == 'wms.gebco.net') return gebco();
      return http.Response('not found', 404);
    });

http.Response _ok(String body) => http.Response(body, 200);

void main() {
  // Palmižana anchorage (Pakleni otoci, Croatia).
  const palmizana = LatLng(43.15, 16.40);
  // Hvar island hills.
  const hvarLand = LatLng(43.17, 16.60);
  // Mid-Atlantic, outside EMODnet coverage.
  const atlantic = LatLng(40.1013, -40.1031);

  test('water point: EMODnet depth, positive down', () async {
    final calls = <Uri>[];
    final s = DepthService(
      client: _client(
        emodnet: () => _ok(emodnetWater),
        gebco: () => _ok(gebcoHvar),
        calls: calls,
      ),
    );
    final d = await s.depthAt(palmizana);
    expect(d, isNotNull);
    expect(d!.depthM, closeTo(9.89, 0.01));
    expect(d.source, 'EMODnet');
    expect(d.resolution, contains('115'));
    expect(calls, hasLength(1));
    final q = calls.single.queryParameters;
    expect(q['REQUEST'], 'GetFeatureInfo');
    expect(q['QUERY_LAYERS'], 'emodnet:mean');
    expect(q['INFO_FORMAT'], 'application/json');
  });

  test('land point: null, GEBCO not asked', () async {
    final calls = <Uri>[];
    final s = DepthService(
      client: _client(
        emodnet: () => _ok(emodnetLand),
        gebco: () => _ok(gebcoLand),
        calls: calls,
      ),
    );
    expect(await s.depthAt(hvarLand), isNull);
    expect(calls, hasLength(1));
  });

  test('outside EMODnet coverage: GEBCO fallback', () async {
    final calls = <Uri>[];
    final s = DepthService(
      client: _client(
        emodnet: () => _ok(emodnetNoData),
        gebco: () => _ok(gebcoWater),
        calls: calls,
      ),
    );
    final d = await s.depthAt(atlantic);
    expect(d!.depthM, 4648);
    expect(d.source, 'GEBCO');
    expect(calls.last.host, 'wms.gebco.net');
    expect(calls.last.queryParameters['QUERY_LAYERS'], 'GEBCO_LATEST_2');
  });

  test('GEBCO query is centred on a grid cell centre', () {
    final q = DepthService.gebcoUrl(const LatLng(43.0, 16.0)).queryParameters;
    final b = q['BBOX']!.split(',').map(double.parse).toList();
    final lon = (b[0] + b[2]) / 2, lat = (b[1] + b[3]) / 2;
    // 15" cells: centres at (n + 0.5) / 240 degrees.
    double offCentre(double v) => ((v * 240 - 0.5) - (v * 240 - 0.5).round()).abs();
    expect(offCentre(lon), lessThan(1e-3));
    expect(offCentre(lat), lessThan(1e-3));
  });

  test('EMODnet server error falls back to GEBCO', () async {
    for (final bad in [
      () => http.Response(emodnet502, 502),
      () => _ok(emodnetError),
      () => throw http.ClientException('offline'),
    ]) {
      final s = DepthService(
        client: _client(emodnet: bad, gebco: () => _ok(gebcoHvar)),
      );
      final d = await s.depthAt(palmizana);
      expect(d?.depthM, 39);
      expect(d?.source, 'GEBCO');
    }
  });

  test('no data anywhere / both failing: null', () async {
    final s1 = DepthService(
      client: _client(emodnet: () => _ok(emodnetNoData), gebco: () => _ok(gebcoNoResult)),
    );
    expect(await s1.depthAt(atlantic), isNull);
    final s2 = DepthService(
      client: _client(
        emodnet: () => throw http.ClientException('offline'),
        gebco: () => throw http.ClientException('offline'),
      ),
    );
    expect(await s2.depthAt(palmizana), isNull);
  });

  test('timeout: null after the per-request timeout', () async {
    final never = Completer<http.Response>();
    final s = DepthService(
      timeout: const Duration(milliseconds: 50),
      client: _client(emodnet: () => never.future, gebco: () => never.future),
    );
    final sw = Stopwatch()..start();
    expect(await s.depthAt(palmizana), isNull);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test('parsers', () {
    expect(DepthService.parseEmodnet(emodnetWater), closeTo(-9.89, 0.01));
    expect(DepthService.parseEmodnet(emodnetLand), greaterThan(0));
    expect(DepthService.parseEmodnet(emodnetNoData), isNull);
    expect(DepthService.parseEmodnet(emodnetError), isNull);
    expect(DepthService.parseEmodnet('{"features":[]}'), isNull);
    expect(DepthService.parseGebco(gebcoWater), -4648);
    expect(DepthService.parseGebco(gebcoLand), 218);
    expect(DepthService.parseGebco(gebcoNoResult), isNull);
    expect(DepthService.parseGebco(''), isNull);
  });
}
