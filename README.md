# Anchor Alarm

Cross-platform anchor watch for sailors — **iOS, Android and Web** from one Flutter
codebase. Drop anchor, tell the app how much rode is out, and it watches the boat's
position all night. If the boat leaves the swing circle, GPS is lost or the battery
runs low, a loud alarm sounds.

- Product spec: [docs/SPEC.md](docs/SPEC.md) (captured from the project's planning doc)
- Design, scope and alarm defaults: [docs/DESIGN.md](docs/DESIGN.md)
- What to verify on real phones: [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md)
- Demo video (1:44, narrated, GPS simulator): [docs/anchor-alarm-demo.mp4](docs/anchor-alarm-demo.mp4)

## Status

Phase 1 — **core anchor watch** — is implemented:

| Feature | |
|---|---|
| Set anchor from where the boat settles (bow direction from compass), at the boat, or by long-press / drag on the map | ✅ |
| Alarm radius from rode + depth + boat length + GPS margin, slider override | ✅ |
| Warning + alarm rings (green / amber / red), alarm delay, GPS averaging with glitch rejection | ✅ |
| GPS lost / poor GPS / low & critical battery alerts | ✅ |
| Loud looping alarm (plays on silent), vibration, notifications with *Silence* action, snooze | ✅ |
| Background tracking (Android foreground service, iOS background location) | ✅ needs device testing |
| Resume after app restart; Android "interrupted by reboot" alarm notification | ✅ needs device testing |
| Profiles: Lunch stop / Overnight / Storm watch + custom | ✅ |
| Learn-swing *suggestion* during the first 15 min (never auto-applied) | ✅ |
| History with track, alerts, notes | ✅ |
| OpenStreetMap + OpenSeaMap seamarks + satellite; offline tile cache and area download (mobile) | ✅ |
| Day / red night theme, metric/imperial | ✅ |
| Web: full app in the foreground + **GPS simulator** (swing, drag, glitches, poor GPS, GPS loss) | ✅ |

Next phases (designed for, not built): remote monitoring & sharing (backend not yet
chosen — everything goes through `RemoteSync`), weather & forecast alerts, NMEA/AIS,
sensor fusion.

## Run it

Requires Flutter 3.47 (stable).

```sh
flutter pub get
flutter test                      # 169 unit, controller and widget tests
flutter run -d chrome             # web; enable Settings → "Use GPS simulator" to demo
flutter run                       # connected Android / iOS device
flutter build web --release --no-web-resources-cdn
# demo build that starts with the GPS simulator:
flutter build web --release --no-web-resources-cdn --dart-define=DEMO=true
```

Try it without a boat: in **Settings → Use GPS simulator**, drop anchor, start the
watch, then pick *Dragging* from the simulator chip (top left). The alarm sounds in
about a minute.

## Layout

```
lib/domain/    pure Dart: geo maths, models, AnchorWatchEngine (deterministic), track recorder
lib/app/       Riverpod providers, WatchController (location → engine → alarm/notify/store)
lib/services/  platform glue: location, compass, alarm audio, notifications, battery,
               fail-safe (Android boot receiver), storage (sembast), map tile cache, simulator
lib/ui/        screens and widgets
test/          domain, controller, storage and widget tests
```

CI (`.github/workflows/ci.yml`): analyze, test, web build, Android debug APK and an
unsigned iOS build.

## Map data

© OpenStreetMap contributors · Seamarks © OpenSeaMap · Imagery © Esri, Maxar, Earthstar
Geographics. Bulk tile download is deliberately limited (OSM tile usage policy).
