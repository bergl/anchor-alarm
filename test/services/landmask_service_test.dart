import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anchor_alarm/domain/exposure.dart';
import 'package:anchor_alarm/services/map/landmask_service.dart';
import 'package:anchor_alarm/services/map/landmask_store_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

// PNGs recorded from the real servers (2026-10-20) with exactly the requests
// LandMaskService sends (9 km square, 180 px, EPSG:3857):
//   emodnet_pakleni.png  emodnet:mean_multicolour around 43.165, 16.395
//   emodnet_open_sea.png emodnet:mean_multicolour around 42.5, 15.5 (Adriatic)
//   emodnet_atlantic.png emodnet:mean_multicolour around 30, -40 (outside
//                        EMODnet coverage: fully transparent)
//   gebco_pakleni.png / gebco_atlantic.png  GEBCO_LATEST_2, same squares.
Uint8List fixture(String name) =>
    File('test/fixtures/landmask/$name.png').readAsBytesSync();

/// Pakleni channel, west of Hvar town, just north of Sv. Klement.
const pakleni = LatLng(43.1673, 16.3942);
const openSea = LatLng(42.5012, 15.4991);
const atlantic = LatLng(30.0, -40.0);

http.Response png(Uint8List b) =>
    http.Response.bytes(b, 200, headers: {'content-type': 'image/png'});

/// Serves the fixture matching the requested layer and bbox.
MockClient fixtureClient(List<Uri> log, {bool emodnetDown = false}) => MockClient((req) async {
      log.add(req.url);
      final q = req.url.queryParameters;
      final layer = q['LAYERS'];
      final bbox = q['BBOX']!;
      final place = bbox.startsWith('1818913') // around 43.165, 16.395
          ? 'pakleni'
          : bbox.startsWith('1719348') // around 42.5, 15.5
              ? 'open_sea'
              : bbox.startsWith('-4457975') // around 30, -40
                  ? 'atlantic'
                  : null;
      if (place == null) return http.Response('no fixture for $bbox', 404);
      if (layer == 'emodnet:mean_multicolour') {
        if (emodnetDown) return http.Response('<html>502 Bad Gateway</html>', 502);
        return png(fixture('emodnet_$place'));
      }
      if (layer == 'GEBCO_LATEST_2') {
        if (place == 'open_sea') return http.Response('missing', 404);
        return png(fixture('gebco_$place'));
      }
      return http.Response('unknown layer', 400);
    });

void main() {
  test('request: rounded centre, 9 km square in EPSG:3857, 180 px', () {
    final s = LandMaskService();
    final c = s.roundedCentre(pakleni);
    expect(c, const LatLng(43.165, 16.395));
    final u = s.emodnetUrl(c);
    expect(u.host, 'ows.emodnet-bathymetry.eu');
    expect(u.queryParameters['LAYERS'], 'emodnet:mean_multicolour');
    expect(u.queryParameters['SRS'], 'EPSG:3857');
    expect(u.queryParameters['WIDTH'], '180');
    expect(u.queryParameters['TRANSPARENT'], 'true');
    expect(u.queryParameters['BBOX'], '1818913.48,5330950.78,1831252.62,5343289.91');
    expect(s.gebcoUrl(c).queryParameters['LAYERS'], 'GEBCO_LATEST_2');
    expect(s.metresPerPixel, 50);
  });

  test('Pakleni: EMODnet mask and shelter by sector', () async {
    final log = <Uri>[];
    final s = LandMaskService(client: fixtureClient(log));
    final mask = (await s.maskAround(pakleni))!;
    expect(mask.source, 'EMODnet');
    expect(mask.width, 180);
    expect(mask.isWaterAt(pakleni), isTrue);
    // Sv. Klement (south) and Hvar (north-east) are land.
    expect(mask.isWaterAt(const LatLng(43.155, 16.385)), isFalse);
    expect(mask.isWaterAt(const LatLng(43.19, 16.44)), isFalse);
    // Open water to the west (towards Šolta).
    expect(mask.isWaterAt(const LatLng(43.18, 16.36)), isTrue);
    final land = mask.width * mask.height - mask.waterCount;
    expect(land / (mask.width * mask.height), inInclusiveRange(0.2, 0.5));

    final p = computeExposure(mask, pakleni)!;
    SectorExposure sec(String n) => p.sectors[compass16.indexOf(n)];
    // Sv. Klement a few hundred metres to the south.
    for (final n in ['S', 'SSW', 'SSE']) {
      expect(sec(n).rating, ShelterRating.sheltered, reason: '$n ${sec(n).fetchM}');
    }
    // The Pakleni channel opens to the W/NW (towards Šolta / Split channel).
    for (final n in ['WNW', 'NW']) {
      expect(sec(n).rating, ShelterRating.exposed, reason: '$n ${sec(n).fetchM}');
    }
    expect(p.forWindFrom(315).rating, ShelterRating.exposed); // maestral
    expect(p.forWindFrom(180).rating, ShelterRating.sheltered); // jugo
    // Print for the record (report / DESIGN.md).
    // ignore: avoid_print
    print('Pakleni: ${p.describe()}\n'
        '${[for (final x in p.sectors) '${x.name} ${x.fetchM.round()} m ${x.rating.name}'].join('\n')}');
    expect(log, hasLength(1)); // EMODnet only.
  });

  test('open sea: all water, exposed all round', () async {
    final s = LandMaskService(client: fixtureClient([]));
    final mask = (await s.maskAround(openSea))!;
    expect(mask.waterCount, 180 * 180);
    final p = computeExposure(mask, openSea)!;
    expect(p.sectors.every((x) => x.rating == ShelterRating.exposed), isTrue);
  });

  test('outside EMODnet coverage: GEBCO fallback (colour rule)', () async {
    final log = <Uri>[];
    final s = LandMaskService(client: fixtureClient(log));
    final mask = (await s.maskAround(atlantic))!;
    expect(mask.source, 'GEBCO');
    expect(mask.waterCount, 180 * 180);
    expect(log.map((u) => u.host), ['ows.emodnet-bathymetry.eu', 'wms.gebco.net']);
  });

  test('EMODnet down: GEBCO mask of Pakleni agrees roughly with EMODnet', () async {
    final s = LandMaskService(client: fixtureClient([], emodnetDown: true));
    final g = (await s.maskAround(pakleni))!;
    expect(g.source, 'GEBCO');
    final e = LandMaskService.decodeEmodnet(
        fixture('emodnet_pakleni'), g.centre, g.metresPerPixel)!;
    var same = 0;
    for (var y = 0; y < 180; y++) {
      for (var x = 0; x < 180; x++) {
        if (e.isWaterPx(x, y) == g.isWaterPx(x, y)) same++;
      }
    }
    // GEBCO is a ~460 m grid: coastlines differ, the picture does not.
    expect(same / (180 * 180), greaterThan(0.85));
    final p = computeExposure(g, pakleni);
    expect(p, isNotNull);
    expect(p!.forWindFrom(315).rating, ShelterRating.exposed);
  });

  test('cached in memory: one request per rounded centre', () async {
    final log = <Uri>[];
    final s = LandMaskService(client: fixtureClient(log));
    final a = s.maskAround(pakleni);
    final b = s.maskAround(const LatLng(43.1660, 16.3950)); // same centre, in flight
    expect(identical(await a, await b), isTrue);
    await s.maskAround(pakleni);
    expect(s.cached(pakleni), isNotNull);
    expect(log, hasLength(1));
  });

  test('stored masks are used without network', () async {
    final store = MemoryLandMaskStore();
    await LandMaskService(client: fixtureClient([]), store: store).maskAround(pakleni);
    expect(store.entries, hasLength(1));
    final offline = LandMaskService(
      client: MockClient((_) async => throw const SocketException('offline')),
      store: store,
    );
    final mask = await offline.maskAround(pakleni);
    expect(mask, isNotNull);
    expect(mask!.source, 'EMODnet');
  });

  test('file store round trip', () async {
    final dir = await Directory.systemTemp.createTemp('landmask');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileLandMaskStore(dir: () async => dir);
    await LandMaskService(client: fixtureClient([]), store: store).maskAround(pakleni);
    // The write is not awaited by the service: poll until it lands (slow CI).
    Iterable<File> written() =>
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    for (var i = 0; i < 100 && written().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(written(), hasLength(1));
    final again = await LandMaskService(
      client: MockClient((_) async => http.Response('down', 503)),
      store: store,
    ).maskAround(pakleni);
    expect(again?.width, 180);
  });

  test('never throws: offline, errors, junk, timeout → null', () async {
    for (final client in [
      MockClient((_) async => throw const SocketException('offline')),
      MockClient((_) async => http.Response('<ServiceExceptionReport/>', 200,
          headers: {'content-type': 'application/vnd.ogc.se_xml'})),
      MockClient((_) async => http.Response.bytes([1, 2, 3], 200,
          headers: {'content-type': 'image/png'})),
      MockClient((_) async => http.Response('', 500)),
    ]) {
      expect(await LandMaskService(client: client).maskAround(pakleni), isNull);
    }
    final slow = LandMaskService(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );
    expect(await slow.maskAround(pakleni), isNull);
  });
}
