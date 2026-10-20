import 'dart:math';

import 'package:anchor_alarm/domain/geo.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/domain/watch_engine.dart';
import 'package:anchor_alarm/services/remote/firebase_config.dart';
import 'package:anchor_alarm/services/remote/remote_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const anchor = LatLng(43.5, 16.4);
final t0 = DateTime.utc(2026, 10, 20, 12);

AnchorSession session({DateTime? endedAt}) => AnchorSession(
      id: 's1',
      anchor: anchor,
      radiusM: 50,
      initialRadiusM: 50,
      profile: AlarmProfile.builtIns[1],
      startedAt: t0,
      endedAt: endedAt,
    );

WatchSnapshot snap({
  WatchState state = WatchState.safe,
  Set<AlertReason> reasons = const {},
  bool ringing = false,
  double distance = 30,
}) =>
    WatchSnapshot(
      time: t0,
      state: state,
      reasons: reasons,
      ringing: ringing,
      radiusM: 50,
      warningRadiusM: 45,
      maxDistanceM: distance,
      distanceM: distance,
      position: destination(anchor, 90, distance),
      accuracyM: 5,
    );

RemoteWatchWrite write(WatchSnapshot s, {AnchorSession? sess}) => RemoteWatchWrite.from(
      ownerUid: 'u',
      shareKey: 'K' * 26,
      boatName: 'Kestrel',
      session: sess ?? session(),
      snapshot: s,
      tzOffsetMin: 0,
    );

void main() {
  group('share key and ids', () {
    test('share key is 26 base32 chars (128 bits) and random', () {
      final keys = {for (var i = 0; i < 200; i++) newShareKey()};
      expect(keys, hasLength(200));
      for (final k in keys) {
        expect(k, matches(RegExp(r'^[A-Z2-7]{26}$')));
      }
    });

    test('all-ones key encodes to the expected base32', () {
      final r = _ConstRandom(255);
      expect(newShareKey(r), '77777777777777777777777774');
    });

    test('watch ids are 20 alphanumeric chars', () {
      expect(newWatchId(), matches(RegExp(r'^[A-Za-z0-9]{20}$')));
    });
  });

  group('ShareLink.parse', () {
    const id = 'AbCdEfGhIj0123456789';
    const key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const expected = ShareLink(id, key);

    test('full link', () {
      expect(ShareLink.parse('https://bergl.github.io/anchor-alarm/#join=$id.$key'), expected);
      expect(expected.url, 'https://bergl.github.io/anchor-alarm/#join=$id.$key');
    });
    test('fragment and bare code', () {
      expect(ShareLink.parse('join=$id.$key'), expected);
      expect(ShareLink.parse('  $id.$key \n'), expected);
    });
    test('link inside a message', () {
      expect(ShareLink.parse('Monitor us: https://x.y/#join=$id.$key thanks'), expected);
    });
    test('typed by hand: lower-case key with spaces and dashes', () {
      expect(ShareLink.parse('$id.abcde fghij-klmno pqrst uvwxyz'), expected);
    });
    test('rejects garbage, short keys and invalid characters', () {
      expect(ShareLink.parse(''), isNull);
      expect(ShareLink.parse('hello'), isNull);
      expect(ShareLink.parse('$id.ABCDEFG'), isNull);
      expect(ShareLink.parse('$id.ABCDEFGHIJKLMNOPQRSTUVWXY1'), isNull);
      expect(ShareLink.parse('short.$key'), isNull);
    });
  });

  group('RemoteWatchWrite', () {
    test('carries the snapshot', () {
      final w = write(snap(state: WatchState.alarm, reasons: {AlertReason.drag}, ringing: true, distance: 62));
      final f = w.toFields();
      expect(f['state'], 'alarm');
      expect(f['reasons'], ['drag']);
      expect(f['ringing'], true);
      expect(f['distanceM'], 62);
      expect(f['anchor'], {'lat': 43.5, 'lon': 16.4});
      expect((f['boat'] as Map)['accuracyM'], 5);
      expect(f['radiusM'], 50);
      expect(f['warningRadiusM'], 45);
      expect(f.containsKey('updatedAt'), isFalse, reason: 'the store adds the server time');
    });

    test('an ended session is inactive and silent', () {
      final w = write(snap(state: WatchState.alarm, reasons: {AlertReason.drag}, ringing: true),
          sess: session(endedAt: t0));
      expect(w.state, WatchState.inactive);
      expect(w.ringing, isFalse);
      expect(w.reasons, isEmpty);
      expect(w.endedAt, t0);
    });

    test('boat name is trimmed and capped at 60 chars', () {
      final w = RemoteWatchWrite.from(
        ownerUid: 'u',
        shareKey: 'K' * 26,
        boatName: '  ${'x' * 80}  ',
        session: session(),
        tzOffsetMin: 0,
      );
      expect(w.boatName, hasLength(60));
    });
  });

  group('isMaterialChange', () {
    final base = write(snap());
    test('GPS jitter and small distance changes are not material', () {
      final jitter = write(snap(distance: 31));
      expect(isMaterialChange(base, jitter), isFalse);
    });
    test('state, reasons, ringing, radius, anchor and real movement are', () {
      expect(isMaterialChange(base, write(snap(state: WatchState.warning, reasons: {AlertReason.nearEdge}))), isTrue);
      expect(isMaterialChange(base, write(snap(ringing: true))), isTrue);
      expect(isMaterialChange(base, write(snap(distance: 35))), isTrue);
      final moved = RemoteWatchWrite.from(
        ownerUid: 'u',
        shareKey: 'K' * 26,
        boatName: 'Kestrel',
        session: session().copyWith(anchor: destination(anchor, 0, 5)),
        snapshot: snap(),
        tzOffsetMin: 0,
      );
      expect(isMaterialChange(base, moved), isTrue);
      expect(isMaterialChange(base, base.copyWith(shareKey: 'L' * 26)), isTrue);
    });
  });

  group('RemoteWatch and freshness', () {
    RemoteWatch remote({DateTime? updatedAt, DateTime? endedAt}) => RemoteWatch.fromFields('w1', {
          'boatName': 'Kestrel',
          'anchor': {'lat': 43.5, 'lon': 16.4},
          'radiusM': 50,
          'warningRadiusM': 45,
          'boat': {'lat': 43.5001, 'lon': 16.4, 'accuracyM': 4},
          'state': 'alarm',
          'reasons': ['drag', 'unknown'],
          'ringing': true,
          'distanceM': 61.5,
          'updatedAt': updatedAt,
          'endedAt': endedAt,
        });

    test('parses document fields, ignoring unknown values', () {
      final w = remote(updatedAt: t0);
      expect(w.displayName, 'Kestrel');
      expect(w.state, WatchState.alarm);
      expect(w.reasons, {AlertReason.drag});
      expect(w.alarmReasons, {AlertReason.drag});
      expect(w.boat!.latitude, closeTo(43.5001, 1e-9));
      expect(w.accuracyM, 4);
      expect(w.ringing, isTrue);
    });

    test('fresh → stale after 30 s → lost after 3 min; ended wins', () {
      final w = remote(updatedAt: t0);
      expect(freshnessOf(w, t0.add(const Duration(seconds: 30))), Freshness.fresh);
      expect(freshnessOf(w, t0.add(const Duration(seconds: 31))), Freshness.stale);
      expect(freshnessOf(w, t0.add(const Duration(minutes: 3, seconds: 1))), Freshness.lost);
      expect(freshnessOf(remote(updatedAt: t0, endedAt: t0), t0.add(const Duration(hours: 1))),
          Freshness.ended);
    });

    test('updatedAgo', () {
      expect(updatedAgo(t0, t0.add(const Duration(seconds: 2))), 'updated just now');
      expect(updatedAgo(t0, t0.add(const Duration(seconds: 12))), 'updated 12 s ago');
      expect(updatedAgo(t0, t0.add(const Duration(minutes: 4))), 'updated 4 min ago');
      expect(updatedAgo(null, t0), 'updating…');
    });
  });

  group('FirebaseConfig', () {
    test('this test build has no configuration', () {
      final c = FirebaseConfig.fromEnvironment();
      expect(c.isConfiguredFor(RemotePlatform.android), isFalse);
      expect(c.optionsFor(RemotePlatform.web), isNull);
    });

    const full = FirebaseConfig(
      apiKey: 'key',
      appIdAndroid: '1:2:android:3',
      appIdIos: '',
      appIdWeb: '1:2:web:4',
      projectId: 'anchor-alarm-x',
      messagingSenderId: '2',
      storageBucket: '',
      iosBundleId: 'app.anchoralarm.anchorAlarm',
      webAuthDomain: '',
      vapidKey: '',
      useEmulator: false,
      emulatorHost: '127.0.0.1',
    );

    test('configured per platform', () {
      expect(full.isConfiguredFor(RemotePlatform.android), isTrue);
      expect(full.isConfiguredFor(RemotePlatform.ios), isFalse, reason: 'no iOS app id');
      final web = full.optionsFor(RemotePlatform.web)!;
      expect(web.appId, '1:2:web:4');
      expect(web.authDomain, 'anchor-alarm-x.firebaseapp.com');
      expect(web.storageBucket, isNull);
      expect(full.optionsFor(RemotePlatform.android)!.authDomain, isNull);
    });

    test('emulator mode uses the demo project without keys', () {
      const emu = FirebaseConfig(
        apiKey: '',
        appIdAndroid: '',
        appIdIos: '',
        appIdWeb: '',
        projectId: '',
        messagingSenderId: '',
        storageBucket: '',
        iosBundleId: '',
        webAuthDomain: '',
        vapidKey: '',
        useEmulator: true,
        emulatorHost: '10.0.2.2',
      );
      final o = emu.optionsFor(RemotePlatform.android)!;
      expect(o.projectId, 'demo-anchor-alarm');
      expect(emu.isConfiguredFor(RemotePlatform.other), isFalse);
    });
  });
}

class _ConstRandom implements Random {
  _ConstRandom(this.value);
  final int value;
  @override
  int nextInt(int max) => value % max;
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 0;
}
