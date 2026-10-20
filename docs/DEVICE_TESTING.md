# Device testing checklist

Everything here depends on native platform behaviour that cannot be verified in CI or
in the browser. Run it on at least one Android phone (ideally also a Samsung or
Xiaomi — aggressive battery management) and one iPhone before trusting the app at
anchor. Use the GPS simulator for alarm tests where noted; for background tests use
the real GPS.

## Android

1. **Build**: `flutter build apk` succeeds (compileSdk 37, Kotlin boot receiver,
   `MainActivity.popSystemNavigator` override — delete that override if it fails
   to compile with "overrides nothing").
2. **Permissions**
   - Location: "While using" dialog, then the settings page for *Allow all the time*.
   - Notifications (Android 13+).
   - Full-screen intent permission page appears only if not granted (Android 14+).
   - Battery optimisation dialog (Settings → Battery optimisation) and its status.
3. **Background watch** — screen off, 30+ minutes, real GPS:
   - "Anchor watch active" notification with the anchor icon is visible.
   - Fixes keep arriving (~1 s) — check the history track afterwards.
   - Repeat in Doze and on an aggressive OEM device.
4. **Alarm, phone locked, screen off** (simulator → Dragging):
   - Full-screen notification wakes the screen and shows the app over the lock screen.
   - Siren plays at full alarm volume in silent and vibrate mode; original volume is
     restored after *Silence*.
   - Vibration repeats; siren survives other apps' sounds / incoming notifications.
   - *Silence* works from the notification and from the lock screen.
5. **Do Not Disturb**: after granting DnD access, the alarm breaks through DnD.
6. **Back gesture** at the root during a watch sends the app to the background and
   the watch continues.
7. **Reboot during a watch**: "Anchor watch interrupted by restart" appears (before
   and after first unlock) and opens the app, which resumes the watch. Same after an
   app update installed during a watch.
8. **Compass**: bow direction is right with the phone upright and lying flat.

## iOS

1. **Build** with Swift Package Manager succeeds; run on a device.
2. **Location permission**: "While Using", then the "Change to Always Allow" prompt.
3. **Background watch** — locked 30+ minutes: updates continue (blue location
   indicator), not paused automatically.
4. **Alarm while locked** (simulator → Dragging): siren plays with the silent switch on
   and while another app plays music (music ducks). Background vibration is not
   expected (iOS limitation).
5. **Notifications**: time-sensitive alerts break through Focus once allowed;
   *Silence* works from the lock screen; alerts show in the foreground; tapping a
   notification after the app was terminated opens it.
6. Ducking of other apps' audio ends after a warning chime.
7. **Compass** bow direction is correct.
8. Known limitation: after an iPhone restart the app must be reopened (iOS does not
   allow auto-restart).

## Web

1. Browser notifications in Chrome after a button-triggered permission request.
2. The notification service worker does not break loading or offline caching.
3. Screen stays awake while watching with "Keep screen on".

## At anchor (real conditions)

1. Overnight with the default *Overnight* profile: no false alarms; review the track
   in History in the morning.
2. Check the suggested radius against the real swing; note how often the learn-swing
   suggestion appears.
3. Phone placement: inside a cabin / below deck — watch the GPS accuracy figure and
   poor-GPS warnings.
