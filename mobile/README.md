# Elets SalesCall AI — Flutter app

Mobile (Android/iOS) and web client for the Elets SalesCall AI backend in `../backend`.
The REST/WebSocket contract it implements is `../docs/API.md`.

## Stack

Flutter 3.44 / Dart 3.12 · Material 3 · `flutter_riverpod` 3 (no code generation) · `go_router` 18 ·
`dio` · `web_socket_channel` · `flutter_secure_storage` · `fl_chart` · `file_picker` · `just_audio` ·
`url_launcher` · `firebase_messaging` (optional).

```
lib/
  main.dart, app.dart
  core/       config (dart-defines), network (Dio client with refresh, realtime WebSocket),
              storage, theme, router (role guards + shell), push, utils, shared widgets
  features/   auth · dashboard · leads · dialer · calls · followups · ai_agents · campaigns ·
              analytics · team · notifications · profile · settings
              each: data/ (models + repository) → presentation/ (screens, widgets)
```

## Configuration

Everything is passed with `--dart-define`; nothing secret lives in the app (provider and AI keys stay on the server).

| Define | Default | Notes |
|---|---|---|
| `API_BASE_URL` | `http://localhost:8000` | Default backend origin, without `/api/v1`. The WebSocket URL is derived from it (`http→ws`, `https→wss`). Users can change the server on the login screen (**Server: …** → enter address → **Connect**); the choice is saved on the device. |
| `FCM_ENABLED` | `false` | Turn on Firebase Cloud Messaging after adding the Firebase config files (below). |

## Run

Start the backend first (see `../README.md`). Then:

```powershell
flutter pub get
```

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8010
```

Android emulator (the emulator reaches the host machine at `10.0.2.2`):

```powershell
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8010
```

Physical phone on the same Wi-Fi: use the computer's LAN IP, e.g. `--dart-define=API_BASE_URL=http://192.168.1.20:8010`,
and add that origin to the backend's `CORS_ORIGINS` only if you also run the web build.

Android builds allow plain HTTP so the app can reach a server on the office network
(`android:usesCleartextTraffic` in `android/app/src/main/AndroidManifest.xml`). Once the API is served over HTTPS,
set it to `false` in the main manifest. On iOS, local HTTP during development needs an
`NSAppTransportSecurity` exception in `ios/Runner/Info.plist` (don't ship it).

Sign in with an account from the backend seed (see `backend/.env.example` → `SEED_ADMIN_EMAIL` / `SEED_DEFAULT_PASSWORD`).

## Install on an Android phone

1. Build the APK (or use one handed to you): `flutter build apk --release --dart-define=API_BASE_URL=http://<server>:8000`.
   The file is `build/app/outputs/flutter-apk/app-release.apk`.
2. Copy it to the phone (USB, Drive, WhatsApp to yourself, …) and open it. Android asks once to allow installs from
   that app ("Install unknown apps").
3. Start the backend so the phone can reach it: on the server, run uvicorn with `--host 0.0.0.0`, and allow the port
   through the firewall. The phone must be on the same network (or use a public https URL).
4. Open **Elets SalesCall AI**, tap **Server: …** on the sign-in screen if the address needs changing, then sign in.

The release APK is signed with Flutter's debug key, which is fine for installing directly. For the Play Store, create
an upload keystore and configure `signingConfigs` in `android/app/build.gradle.kts`.

iOS builds need a Mac with Xcode and an Apple Developer account (`flutter build ipa`).

## Build

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.your-domain.in
```

```powershell
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.your-domain.in
```

```powershell
flutter build ipa --release --dart-define=API_BASE_URL=https://api.your-domain.in
```

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://api.your-domain.in
```

The web build in `build/web` is static; serve it from any web server and add its origin to the backend's `CORS_ORIGINS`.

Without a local Flutter SDK you can use Docker (from this folder, in Git Bash):

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$PWD:/app" -v elets_pub_cache:/root/.pub-cache -w /app \
  ghcr.io/cirruslabs/flutter:stable sh -c "flutter pub get && flutter analyze && flutter test"
```

## Tests

```powershell
flutter analyze
```

```powershell
flutter test
```

Covers model parsing/round-trips (HumanCall, Lead, Campaign, pagination), formatters and date-range queries,
StatCard / StatusChip / dialer keypad widgets, and the role-based route guard.

## Push notifications (FCM)

In-app notifications already arrive live over the WebSocket. FCM adds pushes while the app is in the background.

1. Create a Firebase project and add Android (`com.elets.salescallai`) and iOS apps.
2. Easiest: `dart pub global activate flutterfire_cli` then `flutterfire configure` in this folder.
   Otherwise put `google-services.json` in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/`,
   and apply the Google Services Gradle plugin per the Firebase docs.
3. iOS: enable Push Notifications and Background Modes → Remote notifications in Xcode, and upload an APNs key to Firebase.
4. Build with `--dart-define=FCM_ENABLED=true`. After sign-in the app registers its token with
   `POST /api/v1/users/me/device-tokens`; the backend sends through the FCM HTTP v1 API
   (`FCM_SERVICE_ACCOUNT_FILE` in the backend `.env`).

## How calling works in the app

* **Human calls (bridge mode).** Tapping Call sends `POST /calls`. The provider rings the salesperson's
  *calling number* (set in Profile) and then connects the lead. The live call screen only opens when the
  backend returns a call with a `provider_call_id`; its status comes from WebSocket `call.status` events with
  a 3-second polling fallback. Mute/speaker are on the phone's own call screen in bridge mode, so the in-app
  buttons are shown disabled with an explanation. When the call ends the outcome sheet opens
  (outcome, notes, follow-up, lead status).
* **Errors are explicit.** `telephony_not_configured`, `opted_out`, `outside_calling_hours`, `lead_busy` and
  provider errors are shown as such; nothing is presented as "calling" unless the provider accepted it.
* **AI Voice Agents** is a separate area (dashboard, agents, campaigns, AI call log with transcript,
  intelligence and recording). Executives see the AI follow-ups routed to them; editing agents and running
  campaigns is admin-only, managers have read access.
* **Recordings and exports** use short-lived signed URLs from the backend, so access is checked and audited.
