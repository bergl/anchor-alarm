# Anchor Alarm — Design & Decisions

Companion to [SPEC.md](SPEC.md) (the captured product spec). This file records what we
build *now*, the decisions taken, and the defaults chosen.

## Scope of the first build (agreed 2026-10-20)

**In:** Phase 1 "Core anchor watch" from the spec:

- Set anchor: *from where the boat settles* (offset from current position by the
  expected swing distance towards the bow) and *long-press / drag on the map*.
- Alarm radius from **rode length + depth** (+ boat length + GPS margin), adjustable
  with a slider; optional **learn swing** that *suggests* a wider radius during the
  first 15 min (capped at +50 %); the user confirms — it is never applied
  automatically, because a dragging anchor looks exactly like a wide swing.
- Warning ring (default 90 % of radius) and alarm ring; green / yellow / red.
- Alarm delay, GPS position averaging, GPS-lost alarm, poor-GPS warning,
  low-battery warning/alarm.
- Loud looping alarm sound + vibration + high-priority local notification;
  silence/snooze; alarm latches until acknowledged.
- Background tracking (Android foreground service, iOS background location mode).
- Fail-safe: active watch persisted and resumed on app restart; on Android a boot
  receiver posts an "Anchor watch interrupted — tap to resume" alarm notification.
- Profiles (Lunch stop / Overnight / Storm watch + custom).
- History log: sessions with anchor, radius, duration, alarms, max distance, notes,
  down-sampled track; detail view on the map.
- Map: OpenStreetMap base + OpenSeaMap seamarks overlay, persistent tile cache and
  "download this area" for offline use; map is optional — alarm never depends on it.
- Day / night (red) theme; units metric + knots by default, switchable.
- **Web**: full app in the foreground (with a "keep this tab open" warning) and a
  **GPS simulator** (drift / drag / swing / GPS loss scenarios) for demos and testing.
  Web will later also be the remote-monitor viewer.

**Deferred (designed for, not built):** remote monitoring & sharing (backend
undecided), weather, NMEA/AIS, sensor fusion/compass-based glitch filtering,
planning assistant, local experience layer.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Framework | Flutter (iOS, Android, Web) | Spec + user choice |
| State | Riverpod | Spec recommends Provider/Riverpod |
| Location | `geolocator` (+ `LocationSource` abstraction) | Spec; abstraction allows simulator, NMEA later |
| Map | `flutter_map` + OSM + OpenSeaMap | Spec recommendation, no API key |
| Tile cache | Own small disk cache (`CachingTileProvider`) | `flutter_map_tile_caching` v10 needs ObjectBox, breaks web |
| Local storage | `sembast` (IO) / `sembast_web` (IndexedDB) | Same API on mobile and web, pure Dart |
| Settings | `shared_preferences` | Simple key-value |
| Alarm sound | `audioplayers` looping asset + `vibration` + `wakelock_plus` | |
| Notifications | `flutter_local_notifications` (alarm channel, full-screen intent on Android, time-sensitive on iOS) | Spec |
| Backend | **Deferred.** All cloud access goes through a `RemoteSync` interface (no-op for now) | User decision |
| Licensing | GPL dependencies are acceptable | User decision |
| Language | English only, `intl`-ready | User decision |

## Architecture

```
lib/
  domain/        pure Dart, no Flutter imports — fully unit tested
    geo.dart            distance, bearing, destination point, swing radius
    models.dart         PositionFix, AlarmProfile, BoatSettings, AnchorSession, ...
    watch_engine.dart   AnchorWatchEngine: fixes in -> WatchSnapshot out
    track_recorder.dart down-sampling of the track
  services/      platform glue behind small interfaces
    location/           LocationSource: GeolocatorSource, SimulatedSource
    alarm/              AlarmOutput (sound, vibration, wakelock), NotificationService
    battery/            BatteryMonitor
    storage/            SettingsRepository, SessionRepository (sembast)
    map/                CachingTileProvider (+ web fallback)
    remote/             RemoteSync interface (no-op)
  app/           Riverpod providers + WatchController orchestrating it all
  ui/            screens and widgets
```

`AnchorWatchEngine` is deterministic: it receives fixes and clock ticks with explicit
timestamps and returns a snapshot. No timers inside — makes it testable and lets the
same engine later run in a background isolate or on a server.

## Alarm logic defaults

| Parameter | Lunch stop | Overnight | Storm watch |
|---|---|---|---|
| Warning ring | 90 % | 90 % | 85 % |
| Alarm delay (must stay outside) | 20 s | 10 s | 5 s |
| Position averaging window | 15 s | 10 s | 5 s |
| GPS lost after | 60 s | 60 s | 30 s |
| Poor GPS (accuracy worse than) | 30 m | 25 m | 20 m |
| Learn swing suggestion (first 15 min, cap +50 %) | on | on | off |
| Low battery warning / alarm | 20 % / 10 % | 20 % / 10 % | 30 % / 15 % |

- **Radius** = √(rode² − depth²) + boat length + GPS margin (default 5 m), min 15 m.
  When the anchor is set "from where the boat settles", anchor point = current
  position moved by √(rode² − depth²) + GPS-to-bow distance along the bow
  direction (compass heading if available, else user drags the anchor on the map).
- Why 90 %: with the default radius the phone normally lies at about
  √(rode² − depth²) + GPS-to-bow from the anchor, i.e. ~75 % of the radius
  (30 m rode, 5 m depth, 12 m boat: 35.6 m of 47 m). An 80 % warning ring sat
  only ~2 m outside the normal lie and GPS noise alone triggered it.
- **Averaging**: accuracy-weighted mean (weight 1/acc²) of the fixes in the window.
- **States**: `safe` → `warning` (inside alarm ring, outside warning ring for the
  delay) → `alarm` (outside alarm ring for the delay). Alarm **latches** until the
  user silences it. Silence = snooze 2 min; still outside afterwards → re-alarm.
- Fixes with accuracy worse than 100 m are ignored for the distance decision.
- **GPS lost**: no usable fix for the configured time → alarm (clears with next fix
  but must still be acknowledged).
- **Poor GPS**: averaged accuracy worse than the threshold for 2 min → warning.

## Platform notes

- **Android**: `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`,
  `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`,
  `WAKE_LOCK`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`. Location stream runs with
  geolocator's foreground-service notification so the Dart isolate stays alive.
  Ask the user to exempt the app from battery optimisation.
- **iOS**: `UIBackgroundModes` = `location`, `audio`; "Always" location
  permission; `allowBackgroundLocationUpdates`, `pausesLocationUpdatesAutomatically
  = false`. Alarm audio uses the playback audio session so it sounds with the silent
  switch on. iOS cannot auto-restart after reboot — documented to the user.
  Critical Alerts need an Apple entitlement (future).
- **Web**: foreground only; Wake Lock API to keep the screen on; banner explaining
  the limitation.

## Remote monitoring (future, backend-agnostic)

`RemoteSync` will publish `{anchor, radius, warningRadius, boatPosition, state,
updatedAt}` about every 5 s and on state changes, and subscribe by share code.
Candidates: Firebase (Firestore + FCM), Supabase (+ FCM/APNs).
