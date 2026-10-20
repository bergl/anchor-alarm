# Firebase setup (remote monitoring)

Remote monitoring ("Share this watch" on the boat, "Monitor a boat" ashore) runs on
Firebase: **Firestore** (live watch data), **Authentication** (anonymous),
**Cloud Messaging** (alarm pushes) and **Cloud Functions** (sends the pushes,
detects lost contact). The code is in the repository; this page is what you do
once in the Firebase console. Until then every build simply shows
*"Remote monitoring is not configured in this build."*

Nothing secret is committed: the app reads its Firebase configuration from
compile-time defines (`--dart-define-from-file=firebase.json`). There is no
`google-services.json`, `GoogleService-Info.plist` or generated
`firebase_options.dart` in the repository, and the Google Services Gradle plugin is
not used — the app initialises Firebase with explicit options.

Time: about 45 minutes, plus waiting for Apple for the APNs key.

---

## 1. Create the project

1. <https://console.firebase.google.com> → **Create a project**.
2. Name: `anchor-alarm` (Firebase appends a suffix to make the **project ID**
   unique, e.g. `anchor-alarm-1a2b3`; note it down).
3. Google Analytics: **off** (not used).

## 2. Upgrade to the Blaze plan

Cloud Functions need the pay-as-you-go **Blaze** plan. For one boat and a few
watchers the usage stays far inside the free quota (a sharing boat writes about
once a minute while nothing happens, every ~5 s while it moves; one scheduled
function run every 5 minutes).

1. Console → ⚙ → **Usage and billing** → **Details & settings** → **Modify plan** → Blaze.
2. **Set a budget alert** right away: Google Cloud console → Billing → **Budgets &
   alerts** → Create budget, e.g. 5 EUR/month with alerts at 50 %, 90 %, 100 %.
   (A budget only alerts; it does not cap spending.)

## 3. Authentication: enable Anonymous

Console → **Build → Authentication** → Get started → **Sign-in method** →
**Anonymous** → Enable → Save.

## 4. Firestore: create the database

Console → **Build → Firestore Database** → **Create database**:

- Edition: **Standard**.
- Database ID: `(default)`.
- Location: **`europe-west1` (Belgium)**. The functions are deployed to
  `europe-west1` (`REGION` in `firebase/functions/src/index.ts`); Firestore
  triggers must be in the database's region. If you pick another location,
  change `REGION` to match before deploying.
- Start in **production mode** (the real rules are deployed in step 8).

## 5. Register the apps

Console → ⚙ **Project settings** → **General** → *Your apps* → **Add app**:

| Platform | Identifier | Nickname |
|---|---|---|
| Android | package name **`app.anchoralarm.anchor_alarm`** | Anchor Alarm Android |
| iOS (Apple) | bundle ID **`app.anchoralarm.anchorAlarm`** | Anchor Alarm iOS |
| Web | — (no Hosting needed; the web app is on GitHub Pages) | Anchor Alarm Web |

(The identifiers are `applicationId` in `android/app/build.gradle.kts` and
`PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project. If they change, register the
new ones.)

Skip the "download config file" and "add SDK" steps — the app does not need
those files. Instead copy the values from **Project settings → General → Your
apps** (each app has a *SDK setup and configuration* box; choose **Config** for
the web app):

## 6. Create `firebase.json` (dart-defines)

```sh
cp firebase.example.json firebase.json      # firebase.json is git-ignored
```

Fill it in:

| Key | Where |
|---|---|
| `FIREBASE_PROJECT_ID` | Project settings → General → Project ID |
| `FIREBASE_MESSAGING_SENDER_ID` | Project settings → Cloud Messaging → Sender ID (= project number) |
| `FIREBASE_STORAGE_BUCKET` | Web app config `storageBucket` (optional, unused) |
| `FIREBASE_API_KEY` | Web app config `apiKey` |
| `FIREBASE_API_KEY_ANDROID` / `_IOS` / `_WEB` | Optional: per-platform keys if Google created separate ones (Android: `current_key` in google-services.json; iOS: `API_KEY` in the plist). Empty = use `FIREBASE_API_KEY`. |
| `FIREBASE_APP_ID_ANDROID` | Android app → App ID (`1:…:android:…`) |
| `FIREBASE_APP_ID_IOS` | iOS app → App ID (`1:…:ios:…`) |
| `FIREBASE_APP_ID_WEB` | Web app config `appId` (`1:…:web:…`) |
| `FIREBASE_IOS_BUNDLE_ID` | `app.anchoralarm.anchorAlarm` |
| `FIREBASE_WEB_AUTH_DOMAIN` | Web app config `authDomain` (`<project>.firebaseapp.com`) |
| `FIREBASE_VAPID_KEY` | Leave empty (web push is not used yet). |

These values identify the project; they are not secrets (Firebase API keys are
designed to ship in apps — access is controlled by the security rules). They are
kept out of git only to keep forks from talking to your project.

API key restrictions (recommended): Google Cloud console → APIs & Services →
Credentials → the key(s) → restrict to the Android app (package +
SHA-1), iOS app (bundle ID) and HTTP referrers `https://bergl.github.io/*` for the
web key.

Build / run with it:

```sh
flutter run --dart-define-from-file=firebase.json
flutter build apk --release --dart-define-from-file=firebase.json
flutter build web --release --no-web-resources-cdn --dart-define-from-file=firebase.json
```

The `firebase.json` in the repository root is this define file; the Firebase CLI
configuration is `firebase/firebase.json` — different files.

## 7. Cloud Messaging: Android and iOS

**Android** — nothing to do: the Cloud Messaging API (V1) is enabled by default
for new projects; the functions use it through the Admin SDK. The app creates the
notification channels the pushes use (`anchor_alarm`, `anchor_warning`,
`anchor_info`) at start-up, so open the app once after installing.

**iOS (needs the Apple Developer account, 99 USD/year)**

1. <https://developer.apple.com/account> → Certificates, IDs & Profiles → **Keys** →
   **+** → name "Anchor Alarm APNs", tick **Apple Push Notifications service
   (APNs)** → Continue → Register → **Download** the `.p8` (only once!). Note the
   **Key ID** and your **Team ID** (top right).
2. Firebase console → Project settings → **Cloud Messaging** → *Apple app
   configuration* → **APNs Authentication Key** → Upload the `.p8`, Key ID, Team ID.
3. Identifiers → `app.anchoralarm.anchorAlarm` → enable **Push Notifications**.
4. In Xcode (`ios/Runner.xcworkspace`) → Runner target → **Signing &
   Capabilities**: select your team, **+ Capability → Push Notifications**, and
   **+ Capability → Background Modes → Remote notifications** (Location updates and
   Audio are already on). This adds `Runner.entitlements` with `aps-environment`;
   commit it. (It was not added in advance because a free personal team cannot sign
   an app with the push entitlement.)
5. Pushes are sent with `interruption-level: time-sensitive`. The user must allow
   *Time Sensitive Notifications* for Anchor Alarm (iOS asks; Settings →
   Notifications → Anchor Alarm). **Critical alerts** (sound even when muted / in
   Do Not Disturb) need the `com.apple.developer.usernotifications.critical-alerts`
   entitlement, which Apple grants on request
   (<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>);
   the payload change is prepared as a comment in `firebase/functions/src/logic.ts`.

**Web** — no web push yet (see DESIGN.md); a browser that monitors a boat sounds the
alarm while the tab is open.

## 8. Deploy rules, indexes and functions

Requires Node 22 and Java 21 (only for the emulators).

```sh
cd firebase/functions
npm ci
npx firebase-tools@15 login
npx firebase-tools@15 deploy --config ../firebase.json --project YOUR_PROJECT_ID \
    --only firestore:rules,firestore:indexes,functions
```

(`npm run deploy -- --project YOUR_PROJECT_ID` does the same.) Or set the project
once: `npx firebase-tools@15 use --add` in `firebase/` (writes `.firebaserc`
aliases; the committed default `demo-anchor-alarm` is the emulator-only demo
project).

The first deploy enables the needed Google Cloud APIs (Cloud Functions, Cloud
Build, Artifact Registry, Eventarc, Cloud Scheduler, Pub/Sub) — accept the
prompts; it can take a few minutes, and a first-time Eventarc permission error
usually goes away when you simply deploy again after a minute.

Check: Firebase console → Functions shows `onWatchUpdated` and
`checkLostContact` (europe-west1); Firestore → Rules shows the deployed rules;
Indexes shows `watches (endedAt, updatedAt)` building/enabled.

Ended watches stay in Firestore (a few hundred bytes each); delete old ones by
hand in the console if you like.

## 9. CI and GitHub Pages

The workflows pass the defines when the repository secret exists, and build
without remote monitoring when it does not.

1. GitHub → repository → Settings → **Secrets and variables → Actions** → New
   repository secret **`FIREBASE_DEFINES_JSON`** = the whole content of your
   `firebase.json` (one JSON object).
2. `.github/scripts/firebase-defines.sh` writes it to `firebase.json` in the runner
   and adds `--dart-define-from-file=firebase.json` to `flutter build web / apk /
   appbundle / ios` in `ci.yml` and `pages.yml`. Pull requests from forks do not see
   the secret and build without Firebase.
3. Web app domain: Firebase console → Authentication → Settings → **Authorized
   domains** → add `bergl.github.io` (anonymous sign-in from the Pages site).
4. The `functions` CI job type-checks and tests `firebase/functions`, including the
   rules and function integration tests on the Firebase Emulator Suite. It needs no
   secret.

## 10. Try it

1. Boat phone: start an anchor watch → the *Adjust radius or profile* button on the
   status card (or the menu → **Share watch**) → **Share this watch** → switch on, enter the boat name →
   QR code + link.
2. Second phone: menu → **Monitor a boat** → paste the link (or open it: it opens
   the web app, which monitors directly) → allow notifications.
3. On the boat phone (simulator: Settings → Use GPS simulator; simulator chip →
   *Dragging*): when the alarm rings, the second phone rings too (live view while
   open; a push notification when it is in the background or closed).
4. Turn the boat phone's network off for > 3 minutes: the monitor shows
   **Lost contact** and gets a push "Lost contact with <boat> — last update 14:05".

## Local development with the emulators (no Firebase project needed)

```sh
cd firebase/functions && npm ci && npm run serve        # auth, firestore, functions
# second terminal, repository root:
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
# Android emulator (host loopback is 10.0.2.2):
flutter run --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

Emulator builds use the demo project `demo-anchor-alarm`, need no keys and have no
pushes (there is no FCM emulator; the functions write the messages they would send
to the `emulatorOutbox` collection instead). Tests:

```sh
cd firebase/functions
npm test                 # decision logic (no emulator)
npm run test:emulator    # security rules + functions against the emulator suite
```
