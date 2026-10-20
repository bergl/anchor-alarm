# Android release builds

CI builds a signed **App Bundle (AAB)** for Google Play and a signed **APK** for
direct install whenever the signing secrets exist. Without them, the job is
skipped and the regular debug APK is still built.

## 1. Decide the application ID (one-way door)

The app currently uses `app.anchoralarm.anchor_alarm`
(`android/app/build.gradle.kts` → `applicationId`). Once an app is published on
Google Play its ID can never change. Pick the final one before the first upload,
e.g. a reverse domain you own.

## 2. Create the upload keystore (once, on your computer)

```sh
keytool -genkeypair -v -keystore upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

Keep `upload.jks` and both passwords in your password manager. If you lose
them you cannot publish updates (Play App Signing lets you reset the upload key
through Google support, but plan not to need it).

## 3. Add the GitHub secrets

Repository → Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | output of `base64 -w0 upload.jks` (macOS: `base64 -i upload.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password |

The next push to `main` produces the `android-release` artifact with
`app-release.aab` and `app-release.apk`. The build number is the CI run number;
the version name comes from `pubspec.yaml`.

## 4. Local release build (optional)

Create `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

then `flutter build appbundle --release`.

## 5. Google Play internal testing

1. Create the app in the Play Console (one-time $25 developer fee).
2. Enable **Play App Signing** (default) and upload `app-release.aab` to an
   *Internal testing* track; add testers by e-mail.
3. Play will ask about permissions. Prepare short justifications:
   - **Background location** (`ACCESS_BACKGROUND_LOCATION`): the anchor watch
     must keep checking the boat's position with the screen off.
   - **Foreground service (location)**: continuous anchor monitoring.
   - **Full-screen intent**: the drag alarm must wake the phone like an alarm clock.
   - A short video of the anchor watch is usually requested for background location.
