import 'package:anchor_alarm/app/app_settings.dart';
import 'package:anchor_alarm/domain/models.dart';
import 'package:anchor_alarm/services/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

AnchorSession session(
  String id, {
  required DateTime startedAt,
  DateTime? endedAt,
  List<AlertEvent> alerts = const [],
}) =>
    AnchorSession(
      id: id,
      anchor: const LatLng(43.5, 16.4),
      radiusM: 40,
      initialRadiusM: 35,
      profile: AlarmProfile.builtIns[1],
      startedAt: startedAt,
      endedAt: endedAt,
      rodeM: 30,
      depthM: 5,
      maxDistanceM: 12.5,
      alerts: alerts,
      notes: 'note',
      name: 'Bay',
    );

TrackPoint point(DateTime t, [double dLat = 0]) =>
    TrackPoint(LatLng(43.5 + dLat, 16.4), t, 4);

void main() {
  late AppDatabase db;
  final t0 = DateTime.fromMillisecondsSinceEpoch(1760000000000);

  setUp(() async => db = await openAppDatabase(inMemory: true));
  tearDown(() => db.close());

  group('SettingsRepository', () {
    test('returns defaults when empty', () async {
      final s = await db.settings.load();
      expect(s.activeProfileId, const AppSettings().activeProfileId);
      expect(await db.settings.loadCustomProfiles(), isEmpty);
    });

    test('round-trips settings', () async {
      final s = const AppSettings().copyWith(
        distanceUnit: DistanceUnit.feet,
        theme: ThemePref.night,
        activeProfileId: AlarmProfile.stormId,
        boat: const BoatSettings(lengthM: 9.5, lastRodeM: 42),
        baseMap: BaseMap.satellite,
        seamarks: false,
        useSimulator: true,
      );
      await db.settings.save(s);
      final l = await db.settings.load();
      expect(l.toJson(), s.toJson());
    });

    test('custom profiles keep order and are replaced on save', () async {
      final a = AlarmProfile.builtIns[0].copyWith(id: 'a', name: 'A', builtIn: false);
      final b = AlarmProfile.builtIns[2].copyWith(id: 'b', name: 'B', builtIn: false);
      final c = const AlarmProfile(id: 'c', name: 'C', alarmDelaySec: 3);
      await db.settings.saveCustomProfiles([b, a, c]);
      expect((await db.settings.loadCustomProfiles()).map((p) => p.id), ['b', 'a', 'c']);

      await db.settings.saveCustomProfiles([c]);
      final l = await db.settings.loadCustomProfiles();
      expect(l.map((p) => p.id), ['c']);
      expect(l.single.alarmDelaySec, 3);
      expect(l.single.toJson(), c.toJson());
    });
  });

  group('SessionRepository', () {
    test('save / get round-trip', () async {
      final s = session('s1', startedAt: t0, alerts: [
        AlertEvent(reason: AlertReason.drag, time: t0, distanceM: 50),
      ]);
      await db.sessions.save(s);
      final l = await db.sessions.get('s1');
      expect(l!.toJson(), s.toJson());
      expect(await db.sessions.get('nope'), isNull);
    });

    test('history contains only ended sessions, newest first', () async {
      await db.sessions.save(session('old', startedAt: t0, endedAt: t0.add(const Duration(hours: 1))));
      await db.sessions.save(session('new',
          startedAt: t0.add(const Duration(days: 1)),
          endedAt: t0.add(const Duration(days: 1, hours: 2))));
      await db.sessions.save(session('active', startedAt: t0.add(const Duration(days: 2))));
      expect((await db.sessions.history()).map((s) => s.id), ['new', 'old']);
    });

    test('loadActive returns null without an active session', () async {
      await db.sessions.save(session('old', startedAt: t0, endedAt: t0.add(const Duration(hours: 1))));
      expect(await db.sessions.loadActive(), isNull);
    });

    test('loadActive returns the newest and closes dangling older ones', () async {
      final t1 = t0.add(const Duration(hours: 5));
      final t2 = t0.add(const Duration(hours: 10));
      await db.sessions.save(session('a', startedAt: t0));
      await db.sessions.save(session('b', startedAt: t1));
      await db.sessions.save(session('c', startedAt: t2));
      await db.sessions.appendTrack('a', [
        point(t0.add(const Duration(minutes: 1))),
        point(t0.add(const Duration(minutes: 30))),
        point(t0.add(const Duration(minutes: 10))),
      ]);

      final active = await db.sessions.loadActive();
      expect(active!.id, 'c');
      expect(active.endedAt, isNull);

      final a = await db.sessions.get('a');
      final b = await db.sessions.get('b');
      expect(a!.endedAt, t0.add(const Duration(minutes: 30)));
      expect(b!.endedAt, t1);
      expect((await db.sessions.history()).map((s) => s.id), ['b', 'a']);
      expect((await db.sessions.loadActive())!.id, 'c');
    });

    test('track is filtered by session and sorted by time', () async {
      await db.sessions.save(session('a', startedAt: t0));
      await db.sessions.save(session('b', startedAt: t0));
      await db.sessions.appendTrack('a', [point(t0.add(const Duration(seconds: 20)), 0.001)]);
      await db.sessions.appendTrack('b', [point(t0.add(const Duration(seconds: 5)))]);
      await db.sessions.appendTrack('a', [
        point(t0.add(const Duration(seconds: 10)), 0.002),
        point(t0.add(const Duration(seconds: 30)), 0.003),
      ]);
      await db.sessions.appendTrack('a', const []);

      final ta = await db.sessions.track('a');
      expect(ta.map((p) => p.time.difference(t0).inSeconds), [10, 20, 30]);
      expect(ta.first.position.latitude, closeTo(43.502, 1e-9));
      expect(ta.first.accuracyM, 4);
      expect(await db.sessions.track('b'), hasLength(1));
      expect(await db.sessions.track('none'), isEmpty);
    });

    test('delete removes the session and its track only', () async {
      await db.sessions.save(session('a', startedAt: t0, endedAt: t0));
      await db.sessions.save(session('b', startedAt: t0, endedAt: t0));
      await db.sessions.appendTrack('a', [point(t0), point(t0.add(const Duration(seconds: 9)))]);
      await db.sessions.appendTrack('b', [point(t0)]);

      await db.sessions.delete('a');
      expect(await db.sessions.get('a'), isNull);
      expect(await db.sessions.track('a'), isEmpty);
      expect(await db.sessions.get('b'), isNotNull);
      expect(await db.sessions.track('b'), hasLength(1));
    });

    test('in-memory databases are isolated', () async {
      await db.sessions.save(session('a', startedAt: t0));
      final other = await openAppDatabase(inMemory: true);
      expect(await other.sessions.get('a'), isNull);
      await other.close();
    });
  });
}
