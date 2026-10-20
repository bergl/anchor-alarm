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
- Map: OpenStreetMap / satellite / EMODnet depth-relief base, optional EMODnet or
  GEBCO depth overlay, OpenSeaMap seamarks overlay, persistent tile cache and
  "download this area" for offline use; map is optional — alarm never depends on it.
- Charted depth at the anchor (EMODnet, GEBCO fallback) prefills the Drop anchor
  depth field as a hint.
- Day / night (red) theme; units metric + knots by default, switchable.
- **Web**: full app in the foreground (with a "keep this tab open" warning) and a
  **GPS simulator** (drift / drag / swing / GPS loss scenarios) for demos and testing.
  Web will later also be the remote-monitor viewer.

**Deferred (designed for, not built):** remote monitoring & sharing (backend
undecided), tides, NMEA/AIS, sensor fusion/compass-based glitch filtering,
planning assistant, local experience layer.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Framework | Flutter (iOS, Android, Web) | Spec + user choice |
| State | Riverpod | Spec recommends Provider/Riverpod |
| Location | `geolocator` (+ `LocationSource` abstraction) | Spec; abstraction allows simulator, NMEA later |
| Map | `flutter_map` + OSM + OpenSeaMap; EMODnet / GEBCO for depth | Spec recommendation, no API key; free, open bathymetry (see "Map layers") |
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
    map/                CachingTileProvider (+ web fallback), TileLayerSpec, DepthService
    weather/            WeatherService (Open-Meteo forecast + marine)
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

## Map layers & charted depth

Goal: real marine data around the GPS position, without API keys. The user sails
mostly in Europe / the Mediterranean, so EMODnet (European seas, fine grid) is the
primary depth source and GEBCO (global, coarser) the fallback. All layers are
`TileLayerSpec`s (`lib/services/map/tile_layer_spec.dart`);
`activeTileLayers(settings)` lists what is drawn (bottom to top: base, depth
overlay, seamarks) and what the offline download saves. Picked from the map's
**Layers** button (bottom sheet) or Settings → Map (same `MapLayerOptions` widget).

| Layer (`key`) | Source / request | Zoom | Licence / attribution |
|---|---|---|---|
| Chart (`osm`) | `tile.openstreetmap.org/{z}/{x}/{y}.png` | ≤19 | ODbL, "© OpenStreetMap contributors" |
| Satellite (`esri_imagery`) | Esri World Imagery `…/tile/{z}/{y}/{x}` | ≤19 | Esri terms, "Esri, Maxar, Earthstar Geographics" |
| Depth relief (`emodnet_base`) | EMODnet WMTS layer `baselayer` (World Base Layer), tile matrix set `web_mercator` (EPSG:3857): `tiles.emodnet-bathymetry.eu/2020/baselayer/web_mercator/{z}/{x}/{y}.png` (ResourceURL `{TileMatrix}/{TileCol}/{TileRow}` = z/x/y) | ≤15 (matrix set levels 0–15) | CC BY 4.0, "EMODnet Bathymetry Consortium" |
| EMODnet depth overlay (`emodnet_depth`) | WMS `ows.emodnet-bathymetry.eu/wms`, layer `emodnet:mean_multicolour`, EPSG:3857, PNG transparent | ≤14 (~115 m grid) | CC BY 4.0, "EMODnet Bathymetry Consortium" |
| GEBCO depth overlay (`gebco_depth`) | WMS `wms.gebco.net/mapserv`, layer `GEBCO_LATEST_2` (grid colour-shaded for elevation), EPSG:3857 | ≤12 (~460 m grid) | Public domain, attribution requested: "GEBCO Compilation Group, GEBCO Grid" |
| Seamarks (`seamarks`) | `tiles.openseamap.org/seamark/{z}/{x}/{y}.png` | ≤18 | CC BY-SA, "© OpenSeaMap contributors" |

- **WMS as tiles**: overlays are rendered with flutter_map's `WMSTileLayerOptions`
  (WMS 1.1.1, 256 px, BBOX = the Web Mercator tile). `TileProvider.getTileUrl`
  builds the WMS URL, and our `CachingTileProvider` keys its disk cache by
  `layer.key/z/x/y`, so overlays are cached and downloadable offline exactly like
  XYZ layers; `WmsSource.getMapUrl(z, x, y)` builds the same request without a
  widget (for downloads).
- **Drawing**: overlays at opacity 0.55 between base map and seamarks; in the night
  theme the whole tile stack goes through the red night filter.
- **Why these layers**: `baselayer` is the only EMODnet WMTS layer with global
  coverage in Web Mercator (the `mean_*` WMTS layers are European only and blank
  elsewhere); it is a shaded relief whose colour ramp spans the oceans, so shallow
  coastal water looks pale — combine it with the EMODnet overlay for anchoring
  depths. `mean_multicolour` gives the most contrast in 0–100 m; contours
  (`emodnet:contours`) were tried and add little at anchorage scale.
  `GEBCO_LATEST_2` is GEBCO's current colour-coded grid and supports
  GetFeatureInfo.
- **Charted depth** (`DepthService`, `lib/services/map/depth_service.dart`):
  WMS GetFeatureInfo on `emodnet:mean` (`INFO_FORMAT=application/json`; property
  `Depth` is an *elevation*: negative = water, positive = land, exactly 0 = no
  data), falling back to GEBCO `GEBCO_LATEST_2` (`text/plain`, `value_list`, also
  elevation). GEBCO's MapServer only answers when the queried pixel is on a grid
  cell centre, so the query is centred on the 15″ cell containing the point.
  5 s timeout per request; null on land / no data / offline. EMODnet land is
  final (GEBCO is coarser). Both servers send `Access-Control-Allow-Origin: *`,
  so lookups also work on the web.
- **Drop anchor prefill**: when the panel opens or the anchor moves ≥ 25 m
  (debounced 600 ms) the charted depth at the anchor is looked up and shown as
  "Charted depth ≈ 6.2 m (EMODnet) — check your sounder". It fills the depth field
  (and so the suggested radius) unless the user already changed the depth in this
  panel session; values under 1 m (grid cells on the coastline) are only shown,
  never used.

## Offline charts

The chart must work at anchor without internet, so when a watch starts the app
saves the chart around the anchor (Settings → Map → "Save chart around anchor
automatically", on by default; mobile only — on the web the browser cache is
all there is). "Download chart around me now" does the same around the boat,
and "Download this map area" still downloads the visible area.

- **Plan** (`OfflineAreaPlanner`, `lib/services/map/offline_area.dart`): three
  square bands around the centre, for every active layer (base map, depth
  overlay, seamarks — `activeTileLayers`), each capped at the layer's max native
  zoom:

  | Band | Zoom | Half side |
  |---|---|---|
  | overview | 10–12 | 15 km |
  | approach | 13–15 | 3 km |
  | anchorage | 16–17 | 600 m |

  ≈190 tiles per layer at 43° N (osm + seamarks ≈380 tiles, ~4 MB; with the
  EMODnet depth overlay ≈450), ≈570 per layer near 68° N.
- **Limit**: a plan never exceeds the downloader's per-run limit
  (`maxDownloadTiles` = 3000). Over budget, outer bands shrink first (to 5 km /
  1 km), then the anchorage band (to 250 m), then outer bands are dropped, and
  finally the anchorage loses zoom levels.
- **Policy** (OSM tile usage policy): modest volumes only, at most 2 parallel
  requests, identifying User-Agent, tiles younger than 30 days are not fetched
  again, only one download runs at a time, and an area whose centre is within
  500 m of one completed in the last 7 days (with the same layers) is not
  downloaded again automatically (`offline_areas.json` in the tile cache
  directory; clearing the cache forgets it).
- **Isolation**: `OfflineAreaController` listens to the watch (session id
  null → set starts, set → null cancels) and catches everything; a failed or
  cancelled download never affects the anchor watch. A chip on the map shows
  progress (tap to stop) and a SnackBar confirms "Chart saved for offline use".

## Weather

Forecast wind, gusts, wind shifts, waves and pressure, so the skipper is warned
*before* conditions change at anchor (Phase 4 of the spec).

- **Source**: [Open-Meteo](https://open-meteo.com) — free, no API key, CORS
  enabled (works on the web). Attribution "Weather data by Open-Meteo.com
  (CC BY 4.0)" in the weather sheet and About.
  - Forecast `api.open-meteo.com/v1/forecast`: `hourly=wind_speed_10m,
    wind_gusts_10m,wind_direction_10m,pressure_msl,precipitation,weather_code`,
    `current=wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl`,
    `wind_speed_unit=kn`, `timezone=auto`, `forecast_days=3`, `past_hours=3`.
  - Marine `marine-api.open-meteo.com/v1/marine`: `hourly=wave_height,
    wave_direction,wave_period` (same time parameters). Optional: an error,
    inland point (all values null) or timeout just means "no waves".
  - Times come back as local wall-clock ISO strings without offset plus
    `utc_offset_seconds`; `WeatherService.parseTime` converts them to UTC.
  - 10 s timeout per request; `fetch` never throws (`WeatherOk` /
    `WeatherError`). Parsed into the pure-Dart `Forecast` model
    (`lib/domain/weather.dart`), JSON-serialisable for the cache.
- **Refresh policy** (`WeatherController`, `lib/app/weather_controller.dart`):
  - Watch starts (or is restored): fetch for the **anchor**; then a 15-min
    tick re-analyses and fetches again when the forecast is ≥ 3 h old or for a
    place > 5 km away; after a failure it retries every 30 min. App resume
    runs the same check. The refresh button fetches at once.
  - Not watching: the weather sheet (map menu → Weather) and the Drop anchor
    panel fetch for the **boat** if the forecast is missing, old (1 h / 3 h) or
    > 5 km away; after a failure the UI waits 5 min before asking again.
  - The last forecast is cached (sembast store `weather`, record `last`), so
    offline the app still shows it: "Forecast from 14:05, 3 h ago", "Offline —
    showing the last forecast".
- **Analysis** (`analyzeWeather`, `lib/domain/weather_risk.dart`, pure Dart):
  the current hour up to now + 24 h. Current conditions = the API's
  `current` block if ≤ 1 h old, else the current hour. Max gust (+ time and
  direction), max sustained wind, max wave height, first wind shift, largest
  pressure fall.

  | Alert | Rule | Default threshold |
  |---|---|---|
  | `strongGusts` | any hourly gust ≥ threshold | 25 kn (Settings → Weather) |
  | `strongWind` | any hourly mean wind ≥ threshold | 20 kn (Settings) |
  | `windShift` | direction changes by > 60° within 6 h, wind ≥ 10 kn at both ends (veer/back, from → to) | fixed |
  | `highWaves` | any hourly wave height ≥ threshold | 1.5 m (Settings) |
  | `pressureDrop` | MSL pressure falls ≥ 3 hPa within 3 h (also in the last 3 h) | fixed |

  Each alert has an onset time (first hour over the threshold / the hour the
  new direction is reached / the start of the first falling window), a peak
  value and time, and a message such as "Gusts to 32 kn expected around 03:00
  from NE (over 25 kn from 02:00)". All thresholds are inclusive (≥), the
  shift angle is strict (> 60°).
- **Notifications**: only while watching and with "Forecast alerts while
  watching" on (default on). An alert is notified **2 h before its onset**, or
  at once when it is closer or already happening, through
  `NotificationService.showInfo` (default importance; several due together are
  combined into one). Each event is notified once: same kind within ±3 h is
  the same event, unless it gets clearly worse (+8 kn gusts/wind, +1 m waves,
  +3 hPa). Forecasts older than 12 h raise no notifications. Weather alerts are
  informational: **they never start the alarm siren** and are independent of
  the drag alarm — a failed fetch never affects the watch.
- **UI**: a line in the watching status ("Wind 12 kn NW · gusts 18 · max
  28 kn 03:00", amber icon — red at night — when an alert is active; "· 4 h
  old" when stale); tap → weather sheet (current conditions, alerts, 24 h wind
  bar/gust chart drawn with a `CustomPainter`, hourly table with wind arrows,
  waves when available, last update + refresh, offline/stale notices,
  attribution). Drop anchor panel: one line "Next 12 h: wind veers NW→NE,
  gusts to 24 kn".
- **Limits**: model forecasts on a ~2–11 km grid — local effects (katabatic
  gusts, bora under mountains, thunderstorms) can be much stronger than
  forecast; the 15-min tick only runs while the app is alive (it is during a
  watch, as a foreground service on Android); `timezone=auto` uses one UTC
  offset per response, so on a DST-change night the hours after the change
  can be off by one hour (switching to `timeformat=unixtime` would avoid it);
  notification dedupe is in memory (an app restart may repeat one); no tides
  yet.

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
