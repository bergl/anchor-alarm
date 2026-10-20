import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/geo.dart';
import 'tile_layer_spec.dart' show tileUserAgent;

enum AnchorageKind { anchorage, anchorBerth, marina }

/// A charted / mapped place to anchor or moor near a position.
class NearbyAnchorage {
  const NearbyAnchorage({
    required this.position,
    required this.kind,
    required this.distanceM,
    this.name,
    this.osmId,
  });

  final LatLng position;
  final AnchorageKind kind;

  /// From the queried position, metres.
  final double distanceM;
  final String? name;

  /// e.g. "node/123", "way/456".
  final String? osmId;

  /// Name, or a generic label for unnamed features.
  String get label =>
      name ??
      switch (kind) {
        AnchorageKind.anchorage => 'Anchorage',
        AnchorageKind.anchorBerth => 'Anchor berth',
        AnchorageKind.marina => 'Marina',
      };

  @override
  String toString() => 'NearbyAnchorage($label, ${kind.name}, ${distanceM.round()} m)';
}

/// Anchorages and marinas near a position. Implementations never throw:
/// null means "unavailable" (offline, server error), an empty list means
/// "none found".
abstract class AnchorageService {
  Future<List<NearbyAnchorage>?> nearby(LatLng p, {double radiusM = 5000});
}

/// No anchorage data (tests, or when disabled).
class NoAnchorageService implements AnchorageService {
  const NoAnchorageService();
  @override
  Future<List<NearbyAnchorage>?> nearby(LatLng p, {double radiusM = 5000}) async => null;
}

/// OpenStreetMap data through the Overpass API: `seamark:type=anchorage`,
/// `seamark:type=anchor_berth` and `leisure=marina` (nodes, ways and
/// relations; areas are reduced to their centre with `out center`).
///
/// Data © OpenStreetMap contributors, ODbL. Overpass is a shared, donated
/// service: one query per check, results cached per ~1 km.
class OverpassAnchorageService implements AnchorageService {
  OverpassAnchorageService({
    http.Client? client,
    this.endpoint = 'https://overpass-api.de/api/interpreter',
    this.timeout = const Duration(seconds: 20),
    this.maxResults = 30,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String endpoint;
  final Duration timeout;
  final int maxResults;
  final _cache = <String, List<NearbyAnchorage>>{};

  /// Overpass QL for features within [radiusM] of [p].
  static String buildQuery(LatLng p, double radiusM, {int timeoutS = 15}) {
    final around = '(around:${radiusM.round()},'
        '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)})';
    return '[out:json][timeout:$timeoutS];\n'
        '(\n'
        '  nwr["seamark:type"~"^(anchorage|anchor_berth)\$"]$around;\n'
        '  nwr["leisure"="marina"]$around;\n'
        ');\n'
        'out center tags;';
  }

  @override
  Future<List<NearbyAnchorage>?> nearby(LatLng p, {double radiusM = 5000}) async {
    final key = '${(p.latitude * 100).round()}_${(p.longitude * 100).round()}_${radiusM.round()}';
    final hit = _cache[key];
    if (hit != null) return _withDistances(hit, p).take(maxResults).toList();
    try {
      final res = await _client.post(
        Uri.parse(endpoint),
        headers: const {'User-Agent': tileUserAgent},
        body: {'data': buildQuery(p, radiusM)},
      ).timeout(timeout);
      if (res.statusCode != 200) return null;
      final list = parse(utf8.decode(res.bodyBytes), p);
      if (list == null) return null;
      _cache[key] = list;
      return list.take(maxResults).toList();
    } catch (_) {
      return null;
    }
  }

  List<NearbyAnchorage> _withDistances(List<NearbyAnchorage> list, LatLng p) => [
        for (final a in list)
          NearbyAnchorage(
            position: a.position,
            kind: a.kind,
            distanceM: distanceM(p, a.position),
            name: a.name,
            osmId: a.osmId,
          ),
      ]..sort((a, b) => a.distanceM.compareTo(b.distanceM));

  /// Parses an Overpass JSON response; results sorted by distance from
  /// [from], features of the same kind and name within 300 m merged (a
  /// marina mapped as node and area). Null for an invalid body.
  static List<NearbyAnchorage>? parse(String body, LatLng from) {
    Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map || json['elements'] is! List) return null;
    final out = <NearbyAnchorage>[];
    for (final e in json['elements'] as List) {
      if (e is! Map) continue;
      final tags = e['tags'];
      if (tags is! Map) continue;
      final pos = _position(e);
      if (pos == null) continue;
      final seamark = tags['seamark:type'];
      final kind = seamark == 'anchorage'
          ? AnchorageKind.anchorage
          : seamark == 'anchor_berth'
              ? AnchorageKind.anchorBerth
              : tags['leisure'] == 'marina'
                  ? AnchorageKind.marina
                  : null;
      if (kind == null) continue;
      String? name;
      for (final k in const ['name', 'seamark:name', 'name:en', 'name:hr', 'name:it']) {
        final v = tags[k];
        if (v is String && v.trim().isNotEmpty) {
          name = v.trim();
          break;
        }
      }
      final a = NearbyAnchorage(
        position: pos,
        kind: kind,
        distanceM: distanceM(from, pos),
        name: name,
        osmId: e['type'] is String && e['id'] is num ? '${e['type']}/${e['id']}' : null,
      );
      final dup = out.indexWhere((o) =>
          o.kind == a.kind && o.name == a.name && distanceM(o.position, a.position) < 300);
      if (dup >= 0) {
        if (a.distanceM < out[dup].distanceM) out[dup] = a;
        continue;
      }
      out.add(a);
    }
    out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return out;
  }

  static LatLng? _position(Map e) {
    num? lat = e['lat'] as num?, lon = e['lon'] as num?;
    final c = e['center'];
    if ((lat == null || lon == null) && c is Map) {
      lat = c['lat'] as num?;
      lon = c['lon'] as num?;
    }
    if (lat == null || lon == null) return null;
    return LatLng(lat.toDouble(), lon.toDouble());
  }

  void close() => _client.close();
}
