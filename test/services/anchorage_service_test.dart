import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anchor_alarm/services/map/anchorage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

// Hand-written fixture in the Overpass JSON format (overpass-api.de is not
// reachable from the build environment, so this is not a recorded response).
final body = File('test/fixtures/overpass/pakleni.json').readAsStringSync();
const pakleni = LatLng(43.1673, 16.3942);

void main() {
  test('query asks for anchorages, anchor berths and marinas around the point', () {
    final q = OverpassAnchorageService.buildQuery(pakleni, 5000);
    expect(q, startsWith('[out:json]'));
    expect(q, contains('nwr["seamark:type"~"^(anchorage|anchor_berth)\$"](around:5000,43.16730,16.39420);'));
    expect(q, contains('nwr["leisure"="marina"](around:5000,43.16730,16.39420);'));
    expect(q, contains('out center tags;'));
  });

  test('parses nodes, way and relation centres; sorted, deduplicated', () {
    final list = OverpassAnchorageService.parse(body, pakleni)!;
    expect(list.map((a) => a.label), [
      'ACI marina Palmižana',
      'Vinogradišće',
      'Anchor berth',
      'Palmižana',
      'Uvala Ždrilca',
    ]);
    final vino = list[1];
    expect(vino.kind, AnchorageKind.anchorage);
    expect(vino.distanceM, closeTo(900, 100));
    expect(vino.osmId, 'node/1001');
    expect(list.first.kind, AnchorageKind.marina);
    expect(list.last.position, const LatLng(43.1661, 16.4211));
    expect(list[2].kind, AnchorageKind.anchorBerth);
    // Buoys and features without a position are ignored.
    expect(list.any((a) => a.name == 'No geometry'), isFalse);
  });

  test('invalid bodies', () {
    expect(OverpassAnchorageService.parse('<html>busy</html>', pakleni), isNull);
    expect(OverpassAnchorageService.parse('{"remark": "x"}', pakleni), isNull);
    expect(OverpassAnchorageService.parse('{"elements": []}', pakleni), isEmpty);
  });

  test('nearby posts the query and caches the result', () async {
    var calls = 0;
    final svc = OverpassAnchorageService(
      client: MockClient((req) async {
        calls++;
        expect(req.method, 'POST');
        expect(req.url.toString(), 'https://overpass-api.de/api/interpreter');
        expect(req.bodyFields['data'], contains('around:5000'));
        return http.Response.bytes(utf8.encode(body), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final a = await svc.nearby(pakleni);
    expect(a, hasLength(5));
    final b = await svc.nearby(const LatLng(43.1675, 16.3945));
    expect(b, hasLength(5));
    expect(calls, 1);
  });

  test('unreachable, busy or slow: null (never throws)', () async {
    for (final client in [
      MockClient((_) async => throw const SocketException('blocked')),
      MockClient((_) async => http.Response('rate limited', 429)),
      MockClient((_) async => http.Response('<html>timeout</html>', 200)),
    ]) {
      expect(await OverpassAnchorageService(client: client).nearby(pakleni), isNull);
    }
    final slow = OverpassAnchorageService(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );
    expect(await slow.nearby(pakleni), isNull);
  });
}
