# ALVI Helium: Engineering Handbook

This handbook covers the ALVI Helium companion app and its ring SDK plugin: setup, architecture, how every feature works, and what still has to be proven on real hardware.

| | |
|---|---|
| Location | `D:\Alvi\alvi_helium` |
| Platforms | Android 8.0+ (API 26) and iOS 13+ (iPhone only for ring features) |
| Hardware | QC Wireless smart ring/band. Android SDK `qring_sdk_1.0.0.60.aar`, iOS `QCBandSDK.framework 1.0.0.20260812` |
| Design source | `D:\Alvi\ALVI Helium App.pdf` (25 screens) |
| Status | App complete. Android debug APK builds. iOS code written but not yet compiled (needs a Mac). Not yet tested against a real band (see §11) |

---

## 1. What Helium is

Helium is a screenless wearable. The band measures sleep, heart rate, HRV, SpO2, skin temperature, stress and movement. The phone turns those readings into four things:

- **A morning readiness score** (0–100), with the reasons behind it
- **Sleep, Heart and Activity views**, each with a one-line plain-language story
- **Workouts** started from the phone or by double-tapping the band, with GPS distance and heart-zone cues
- **A haptic language**: the band speaks back through vibration patterns (in your zone, goal reached, time to move, silent alarm, breathe, battery low)

### Product decisions in this version

- **No account, no sign-in, no subscription.** The *Create your account* step and the *Membership* screen from the design were removed on request.
- **No backend.** Nothing in the app needs a server; see §4 for why.
- **Bilingual.** Every string exists in English and Canadian French.

---

## 2. Step-by-step setup

### 2.1 Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.44.x stable | `flutter --version` |
| JDK | 17+ | Installed here at `C:\Users\ADMIN\jdk\jdk-17.0.20.1+1`. Point Flutter at it with `flutter config --jdk-dir=<path>` |
| Android SDK | API 35/36 platforms | Android Studio or command-line tools. Run `flutter doctor --android-licenses` once |
| Mac + Xcode | Xcode 26+ | iOS only. The vendor framework was built with Xcode 26.4 |
| CocoaPods | latest | iOS only: `sudo gem install cocoapods` |
| Test hardware | Android phone with Bluetooth LE, iPhone, a QC ring/band | The iOS Simulator cannot run ring features |

### 2.2 First build (Android)

```bash
cd D:\Alvi\alvi_helium
flutter pub get
flutter build apk --debug
```

The output is `build/app/outputs/flutter-apk/app-debug.apk`. Install it with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Or run it directly on a connected phone with hot reload:

```bash
flutter run
```

The first Gradle build takes 30–50 minutes because it downloads Gradle and dependencies. Later builds take 3–5 minutes.

### 2.3 First build (iOS, on a Mac)

```bash
cd alvi_helium
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace        # set Signing & Capabilities → Team
flutter run -d <your-iphone-id>
```

The vendor framework contains arm64 device code only. On the Simulator the plugin compiles a stub, so the app runs on sample data only.

### 2.4 Running without a band

On the welcome screen, tap **Explore with sample data**. Every screen fills with realistic generated data from `lib/domain/demo_data.dart`. Pairing a real band later replaces it.

### 2.5 Release builds

1. **Android:**
   - Create an upload keystore and a `signingConfigs.release` block in `android/app/build.gradle.kts`. It currently signs release builds with the debug key.
   - Release builds already enable R8 minify and resource shrinking.
   - The plugin ships the keep rules the vendor SDK needs (`packages/qring_sdk/android/consumer-rules.pro`).
   - Build with `flutter build appbundle`.
2. **iOS:** `flutter build ipa`. The `bluetooth-central` background mode is declared; App Review will ask why. The answer: to keep the wearable connected and synced.
3. **Placeholders to fill before release:**
   - `[CONTACT]`, the privacy officer, in `lib/screens/onboarding.dart` and `lib/screens/you.dart`
   - The real Privacy Policy and Terms links
   - App icons (`android/app/src/main/res/mipmap-*`, `ios/Runner/Assets.xcassets`)
   - The bundle and application id: currently `ca.alvi.alvi_helium`

---

## 3. Architecture

```
┌────────────────────────── Flutter app (lib/) ──────────────────────────┐
│ screens/  ── Today · Sleep · Heart · Activity · You · onboarding · tools│
│    │ watch                                                              │
│ state/    ── AppState (pairing, connection, settings push, cues, backup)│
│              HealthStore (sync, cache, baselines)  WorkoutSession       │
│    │ uses                                                               │
│ domain/   ── models · insights (readiness, sleep score) · haptics       │
└────┼────────────────────────────────────────────────────────────────────┘
     │ package:qring_sdk  (QRing.instance)
┌────▼──────────── Plugin (packages/qring_sdk) ───────────────────────────┐
│ Dart API ── MethodChannel "qring_sdk/methods" + EventChannel "…/events" │
│  Android: QringSdkPlugin.kt  →  qring_sdk_1.0.0.60.aar (com.oudmon.*)   │
│  iOS:     QringSdkPlugin.m   →  QCBandSDK.framework (static, arm64)     │
└────┼────────────────────────────────────────────────────────────────────┘
     │ Bluetooth LE
   [ Ring / band ]
```

### 3.1 Repository layout

| Path | What it contains |
|---|---|
| `lib/main.dart` | Bootstraps prefs, providers and locale. Routes to Welcome or the tab shell |
| `lib/theme/tokens.dart` | Design tokens: colours, Inter and JetBrains Mono, type scale |
| `lib/l10n.dart` | `context.t('English', 'Français')` inline translation helper |
| `lib/widgets/common.dart` | Pill buttons, rows, toggles, stat grids, step and detail scaffolds |
| `lib/widgets/glyphs.dart` | ALVI mark, haptic pattern glyphs, tab icons, band drawings |
| `lib/widgets/charts.dart` | Readiness ring, hypnogram, line, dot and trend charts, zone bars |
| `lib/domain/models.dart` | Profile, prefs, alarm, nightly summary, workouts |
| `lib/domain/insights.dart` | Sleep score, resting HR, baselines, readiness |
| `lib/domain/haptics.dart` | Haptic pattern definitions and playback |
| `lib/domain/demo_data.dart` | Sample-mode generator |
| `lib/state/app_state.dart` | Pairing, connection, auto-reconnect, settings push, cues, backup |
| `lib/state/health_store.dart` | Ring sync, day cache, history, workouts |
| `lib/state/workout_session.dart` | Live workout: ring heart rate, GPS, zones, cues |
| `lib/state/alarm_backup.dart` | Phone-sound alarm backup (scheduled notification) |
| `lib/state/backup_io.dart` | Export and restore backup files |
| `lib/state/weather.dart` | Open-Meteo current weather (no key) |
| `lib/state/permissions.dart` | Bluetooth and location permission requests |
| `lib/screens/*.dart` | One file per area (see §5) |
| `packages/qring_sdk/` | The plugin (see §6) |
| `test/` | Unit tests for insights and backup |
| `README.md`, `TESTING.md`, `HANDBOOK.md` | Docs |

### 3.2 State management

The app uses `provider` with two `ChangeNotifier`s, created in `main.dart`:

- **`AppState`** holds the user profile, preferences, the paired band, connection state, battery and firmware, feature flags and the event log. It listens to `QRing.events` and reacts to them.
- **`HealthStore`** holds detailed data for the last 7 days (also cached on disk) and up to 120 nightly summaries. It computes readiness for each night.

---

## 4. Backend: decision and rationale

**No backend is required, and none was built.**

| Former reason for a server | Status now |
|---|---|
| Sign-in (Apple, Google, email) | Removed on request |
| Membership billing and coaching trial | Removed on request |
| "Baselines survive a new phone" | Replaced by an on-device **backup file** (You › Privacy and data › Export / Restore) |
| Health data processing | Runs on the phone (`insights.dart`) from data read over Bluetooth |
| Firmware updates | Installed from a `.bin` file the tester picks (§5.9) |
| Product-improvement and research consent toggles | Removed: nothing is uploaded, so there is nothing to consent to |

Privacy copy now says *Stored on this phone · app-private storage*. The only network call is weather from `api.open-meteo.com`. It sends a rounded location and nothing else.

**When to add a backend later.** You would need one for cloud sync across devices, a remote firmware catalogue, coaching, or research studies. Each of those needs identity (accounts), consent records and Canadian data residency (PIPEDA and Québec Law 25). The backup format (§8.3) is the natural sync payload when that time comes.

---

## 5. Feature catalogue: what, how and status

**Status legend:**
- ✅ **Built**: compiles, analyzed and unit-tested where possible
- 🔵 **Device**: logic is complete but has to be confirmed on a real band (§11)
- ⚪ **Limited**: constrained by the SDK or firmware

### 5.1 Onboarding (7 steps)

**File:** `screens/onboarding.dart`

| Step | Screen | How it works | Status |
|---|---|---|---|
| — | Welcome | EN/FR switch. *Get started*. *Restore a backup* (file picker → `importBackup`). *Explore with sample data* | ✅ |
| 1 | Language, region, units | Saved in `Prefs` (french, metric, celsius) | ✅ |
| 2 | Privacy | Explains on-device storage. *I agree* continues | ✅ |
| 3 | About you | Name, birth year, height, weight, sex, goals. Validated before Continue. Sent to the band as the user profile | ✅ / 🔵 |
| 4 | Wake the core | Asks for Bluetooth permission (plus location on Android ≤ 11) | 🔵 |
| 5 | Found | Scans 8 s, picks the strongest signal, connects, plays short-long-short on the band. *That's not my band* rescans and skips it | 🔵 |
| 6 | Wear | Wrist or upper arm, size S/M/L, left or right hand. Stored locally | ✅ |
| 7 | Haptic language | Plays each pattern on the band (§5.8) | 🔵 |
| — | Paired | Baseline progress (nights worn out of 7), wear and battery. *Go to Today* | ✅ |

### 5.2 Today

**File:** `screens/today.dart`

| Element | How it works | Status |
|---|---|---|
| Date and battery | Battery comes from `BatteryEvent` or `getBattery` | 🔵 |
| Weather line | `fetchWeather()` (Open-Meteo, last known location) with advice text | ✅ |
| Readiness ring | `HealthStore.readiness` (§7.3). *See why* opens Readiness | ✅ / 🔵 |
| Status and sentence | `readinessStatus` / `readinessSentence`, driven by HRV delta, temperature delta and sleep | ✅ |
| Bottom band | Sleep h:mm, HRV, steps, skin temperature delta | 🔵 |
| Readiness detail | Five factor bars, last 7 days bars, difference from the 14-day average | ✅ |

### 5.3 Sleep

**File:** `screens/sleep.dart`

| Element | How it works | Status |
|---|---|---|
| Hours and window | From `SleepNight` (`getSleep(0)`) | 🔵 |
| Story headline | Short, restless, deep or solid, compared with the past month | ✅ |
| Hypnogram | Segments by stage: awake, REM, light, deep | 🔵 |
| Score, deep, REM | Ring score if present, otherwise `Insights.sleepScore` | ✅ |
| Silent alarm | Window slider 06:00–07:30, weekdays, pattern preview, phone backup. **Save** writes the alarm to the band and schedules the phone backup | 🔵 / ⚪ |

### 5.4 Heart

**File:** `screens/heart.dart`

| Element | How it works | Status |
|---|---|---|
| Latest bpm | Last heart-rate sample. Tap to take a spot reading (`measure(heartRate)`) | 🔵 |
| Today chart | Downsampled heart-rate line, min to max | 🔵 |
| Resting and HRV | Resting = mean of the lowest 10% of night-time heart rate. HRV = mean during sleep | 🔵 |
| Zone minutes | Minutes at or above 60% of max HR over 7 days | 🔵 |
| Oxygen and breathing | Overnight SpO2 line, range. Breathing rate shows "—" because the SDK doesn't provide it | 🔵 / ⚪ |
| Skin temperature | 30-night deviation dots against your own baseline | 🔵 |

### 5.5 Activity and workouts

**Files:** `screens/activity.dart`, `screens/workout.dart`, `state/workout_session.dart`

| Element | How it works | Status |
|---|---|---|
| Steps, goal, ticks | `getActivitySummary(0)`, plus live step pushes from the band | 🔵 |
| Active, distance, energy | From the same summary | 🔵 |
| Recent workouts | App-recorded workouts plus the band's stored sport records, de-duplicated | 🔵 |
| Start workout | Pick a type: run, walk, ride, pool swim or strength | ✅ |
| Live recording | Stopwatch. Ring live heart rate (realtime HR plus workout pushes). Phone GPS distance and pace. Cadence from the band's steps. Energy from the band, or estimated | 🔵 |
| Zone cue | One pulse on entering Z3, the target zone | 🔵 |
| Goal cue | Two pulses at 5 km | 🔵 |
| Double-tap | Two band taps within 700 ms start a run from any tab. Inside a workout, double-tap ends it | 🔵 |
| Summary | Distance, time, pace, kcal, average and max HR, effort, time in zones, cues the band gave. Swim variant included. **Share** sends a text summary through the system share sheet | ✅ |

### 5.6 You

**File:** `screens/you.dart`

| Element | How it works | Status |
|---|---|---|
| Member since, nights worn, streak, weekly readiness | From history | ✅ |
| Your Helium | Battery and days-left estimate, haptics, wear, find band, firmware, diagnostics, unpair | 🔵 |
| Haptics | Strength, per-cue toggles, quiet hours, *Feel them again* | 🔵 |
| Profile and baselines | Edits About-you and re-sends the profile to the band | 🔵 |
| Privacy and data | Storage explanation, export backup, restore backup, delete all data | ✅ |
| Language | EN/FR toggle | ✅ |
| Diagnostics | Tester tools (§5.10) | ✅ |

### 5.7 Pushed to the band on every connect

`AppState._onReady` runs these in order. Each line is written to the event log as `ok` or `fail`:

1. `syncTime`: sets the clock and reads the feature list
2. User profile (sex, age, height, weight, units)
3. Step goal
4. Touch events on, if the band supports touch
5. Battery
6. Firmware and hardware versions
7. `applyRingSettings()`:
   - Auto-measure heart rate every 10 minutes
   - SpO2, HRV, stress and temperature every 30 minutes, when supported
   - Quiet hours, as the band's do-not-disturb window
   - Move nudges, as the band's sedentary reminder (09:00–21:00, every 60 minutes)
   - Silent alarm, at the end of the window, on the chosen weekdays
8. A full history sync (§7.1)

### 5.8 Haptic language

**File:** `domain/haptics.dart`. Patterns are sequences of buzz and rest, sent through `QRing.vibrate`.

| Pattern | Meaning | Who triggers it |
|---|---|---|
| One pulse | In your zone | App, during a workout |
| Two pulses | Goal reached | App: daily step goal or workout distance |
| One long pulse | Time to move | **Band** (sedentary reminder) |
| Rising pulses | Silent alarm | **Band** (alarm) |
| Slow swell | Breathe | App: stress ≥ 70 within the last 45 minutes, at most once every 2 hours |
| Short, then long | Battery low | App: battery under 15% and not charging, once per discharge |
| Tick | Got it | App, at the end of a workout |

The app-side cues respect quiet hours and only fire while the app is running. Strength is approximated by pulse length, because the motor has a single amplitude.

### 5.9 Firmware update

**File:** `screens/device_tools.dart` → `FirmwareScreen`

1. Requires the band to be connected and at 30% battery or more.
2. The tester picks a vendor `.bin` file.
3. The app copies it to app storage and calls `startOta(path)`.
4. Progress arrives through `OtaProgressEvent`. The band reboots and reconnects when done.

- **Android path:** `DfuHandle` state machine (init → sendPacket → check → end).
- **iOS path:** `syncOtaBinData`.
- **Status:** 🔵

### 5.10 Diagnostics (for testers)

**File:** `screens/device_tools.dart` → `DiagnosticsScreen`. Open it from You › Diagnostics or Your Helium › Diagnostics.

- **Facts:** connection state, id, name, MAC, battery, versions, feature flags, last sync time
- **One-tap commands:**
  - Reconnect, sync, push settings, battery, versions, features
  - Find band, vibrate, play patterns, read alarms
  - All six spot measurements and live heart rate
- **Raw history** for any day from 0 to 6: what the SDK returned for each metric, with sample counts, time range and min, max and last values
- **Event log:** every native event and command result. The copy icon puts the whole log on the clipboard.

### 5.11 Backup, restore and delete

- **Export:** the backup JSON is written to a temporary file, then the system share sheet opens (Files, Drive, email…).
- **Restore:** file picker → format and version check → replaces the profile, settings, paired band and history, then reconnects.
- **Delete all data:** unpairs the band, clears all storage and returns to Welcome.

---

## 6. The plugin (`packages/qring_sdk`)

### 6.1 Dart API

```dart
final ring = QRing.instance;
ring.events / ring.rawEvents            // typed / raw pushes
ring.startScan(); ring.scanResults; ring.stopScan();
ring.connect(id); ring.disconnect(); ring.unbind(); ring.isConnected();
ring.syncTime() → RingFeatures; getBattery(); getVersions();
ring.setUserProfile(...); setGoals(...);
ring.getSleep(d); getHeartRate(d); getHrv(d); getSpO2(d); getTemperature(d); getStress(d);
ring.getBloodPressure(d); getActivitySummary(d); getActivityDetail(d); getWorkouts(d);
ring.measure(type); cancelMeasure(type); startRealtimeHeartRate(); stopRealtimeHeartRate();
ring.workout(action, sportType:);
ring.vibrate(...); findDevice(); setTouchEvents(bool);
ring.setAutoMeasure(metric, ...); setAlarm(...); getAlarms(); setDoNotDisturb(...); setSedentaryReminder(...);
ring.factoryReset(); startOta(path);
```

`d` is a day index: 0 is today, up to 6 days back. Rings keep about 7 days.

### 6.2 Event types

| `event` | Payload |
|---|---|
| `scanResult` | id, name, rssi, mac |
| `scanStopped` | — |
| `connection` | state: `disconnected`, `connecting`, `connected` or `ready` |
| `battery` | level, charging |
| `versions` | firmware, hardware |
| `realtimeHeartRate` | bpm |
| `measurementProgress` | type, value |
| `workout` | state, durationSec, heartRate, steps, distanceM, kcal |
| `touch` | gesture: `tap`, `swipeUp`, `swipeDown` or `longPress` |
| `dataUpdated` | kind, plus steps, distanceM and kcal when kind is `steps` |
| `ota` | percent, done, error |
| `bluetooth` | on |

### 6.3 Android implementation

**File:** `android/src/main/kotlin/.../QringSdkPlugin.kt`

- **Init, once per process.** The plugin registers the SDK's `QCBluetoothCallbackCloneReceiver` subclass (`RECEIVER_NOT_EXPORTED`), then calls `BleOperateManager.getInstance(app).init()`, and registers a Bluetooth adapter receiver. Note the SDK's inverted `setBluetoothTurnOff` flag.
- **Ready means `onServiceDiscovered`.** At that point the plugin calls `LargeDataHandler.initEnable()`, registers device and sport notify listeners, waits 600 ms, then emits `ready`.
- **Commands** go through `CommandHandle.executeReqCmd`. The SDK has no timeouts, so the plugin adds its own (8–30 s) and makes sure each result is answered once.
- **Threading.** Every callback is posted to the main looper before it reaches Flutter.
- **Packaging.** AGP rejects a local `.aar` in a library module, so the AAR is served from `android/libs-maven` as a file Maven repo. The app's `android/build.gradle.kts` must declare that repo.

### 6.4 iOS implementation

**File:** `ios/Classes/QringSdkPlugin.m`, written in Objective-C so it calls the SDK's selectors exactly as declared.

- **The plugin owns `CBCentralManager`.** On `didConnect` it calls `addPeripheral:finished:`. Ready means the SDK reported success.
- **Serial command queue with timeouts.** The SDK fails concurrent calls with error 1001.
- **Live callbacks** are single-slot blocks on `QCSDKManager`, so they are installed once and fanned out to Flutter.
- **Simulator.** Everything is wrapped in `#if !TARGET_OS_SIMULATOR`; the Simulator build gets a stub.
- **Linking.** The podspec links the static framework only for `iphoneos` builds, with `-ObjC`.

---

## 7. Data and algorithms

### 7.1 Sync

`HealthStore.sync` runs on ready, on app resume, on pull-to-refresh, and 20 s after the band reports new data.

- Day 0 is always re-fetched.
- Days 1–6 are fetched only if they are missing.
- For each day it requests sleep, heart rate, HRV, SpO2, temperature, stress, the activity summary and workouts. Metrics the band doesn't support are skipped.
- Each request fails on its own without stopping the rest of the sync.

### 7.2 Sleep score (when the band doesn't provide one)

`insights.dart` → `sleepScore`, out of 100:

| Component | Points | How it's scored |
|---|---|---|
| Duration | 50 | Full marks at 8 h |
| Deep sleep | 20 | Full marks at 18% of total sleep |
| REM | 20 | Full marks at 22% of total sleep |
| Calm | 10 | 10 minus the awake percentage |

### 7.3 Readiness

`insights.dart` → `readiness`. Each factor is scored 0–1 against a 14-night personal baseline:

| Factor | Weight | Rule |
|---|---|---|
| Sleep | 35% | Sleep score ÷ 100 |
| HRV balance | 25% | 0.6 + (HRV ÷ baseline − 1) × 2.5 |
| Resting HR | 20% | 0.65 + (baseline − resting HR) ÷ 12 |
| Recent load | 10% | 0.75 − (yesterday's steps ÷ baseline − 1) × 0.5 |
| Skin temperature | 10% | 1 − abs(deviation) ÷ 1 °C |

Readiness is 0 (no data) when the band wasn't worn that night. These weights are a first pass for product tuning, not a validated model.

### 7.4 Storage

`shared_preferences` keys:

| Key | Contents |
|---|---|
| `profile`, `prefs`, `onboarded` | App settings |
| `device.id`, `device.name`, `device.mac` | The paired band |
| `health.history` | Up to 120 nightly summaries |
| `health.workouts` | App-recorded workouts |
| `health.days` | Detailed data for the last 7 days |
| `goal.YYYY-MM-DD` | Whether the goal cue already fired that day |

### 7.5 Backup file format

```json
{ "format": "helium-backup", "version": 1, "exportedAt": "…",
  "profile": {…}, "prefs": {…}, "device": {"id","name","mac"},
  "health": { "history": [...], "workouts": [...], "days": [...] } }
```

---

## 8. Permissions

| Platform | Permission | Why |
|---|---|---|
| Android 12+ | `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT` | Find and talk to the band |
| Android ≤ 11 | `ACCESS_FINE_LOCATION` | Required by the OS for BLE scans |
| Android | `ACCESS_FINE_LOCATION` (all versions) | Workout GPS distance, weather |
| Android 13+ | `POST_NOTIFICATIONS`, plus `RECEIVE_BOOT_COMPLETED` | Alarm phone backup |
| iOS | `NSBluetoothAlwaysUsageDescription`, `bluetooth-central` background mode | Band connection |
| iOS | `NSLocationWhenInUseUsageDescription` | Workout GPS, weather |
| iOS | Notifications (asked when phone backup is turned on) | Alarm backup |

---

## 9. Localization

All UI strings are inline pairs: `context.t('English', 'Français')`. Dates use `intl` with the `en_CA` and `fr_CA` locales. To add a string, write both languages in the same call.

---

## 10. Automated checks

```bash
flutter analyze            # app: 0 issues
cd packages/qring_sdk && flutter analyze   # plugin: 0 issues
flutter test               # 4 tests: sleep score, readiness, backup round-trip, bad backup rejected
flutter build apk --debug  # Android build incl. plugin Kotlin against the AAR
```

What these checks don't cover:
- **iOS Objective-C compilation:** needs Xcode.
- **Anything involving real Bluetooth:** needs a band.

---

## 11. What's left for live device testing

The step-by-step checklist is in `TESTING.md`. The items below are the open questions: they could not be settled from documentation alone. Each one lists how to check it in Diagnostics and where to change the code if it's wrong.

| # | Question | How to check | Where to fix if wrong |
|---|---|---|---|
| 1 | Are sleep times seconds or milliseconds? | Diagnostics › history › *sleep* start and end match the vendor app | Android `QringSdkPlugin.kt` `toMs()` (line ~624) |
| 2 | Is HRV raw, or raw × 10? | HRV should read 20–120 ms | Android `getHrv()` (line ~396): divide values by 10. iOS uses the SDK's newer per-sample HRV values |
| 3 | Is stress 0–100? | *stress* line | Android `getStress()` (line ~402) |
| 4 | Are calories kcal or small calories? | Activity kcal against the vendor app | Android `/ 1000.0` (lines ~362, 379, 446). iOS `+kcal:` heuristic (line ~765) |
| 5 | Are heart-rate, SpO2 and temperature slots spaced at the right interval? | Sample times spread across the day, not bunched at midnight | Android `series()` interval defaults |
| 6 | Is the alarm and reminder weekday order right? | Save an alarm on Mon/Wed/Fri, then *Read alarms* | Android `dayMask()` (line ~295). iOS `week[d % 7]` (lines ~337, 371) |
| 7 | iOS alarm `time` units: minutes, or HHMM? | *Read alarms* shows the minute value you saved, and the band buzzes on time | `QringSdkPlugin.m` `alarm.time` (line ~340) |
| 8 | iOS workout start times (UTC+8 shift) | A workout started at 07:00 shows 07:00 | `QringSdkPlugin.m` Asia/Shanghai shift (line ~531) |
| 9 | Spot measurement settle time (4 s after first value) | Values match the vendor app | Android `measure()` |
| 10 | Double-tap detection | Band tap events arrive as `tap`. Two within 700 ms start a run | `AppState._onEvent`. Some firmware may report a different gesture code |
| 11 | Do sedentary and DND bit-7 "enable" flags apply? | The band nudges after 60 minutes of sitting, and is silent in quiet hours | Android `setSedentary()` |
| 12 | OTA with a vendor `.bin` | Reaches 100%, band reboots and reconnects | `startOta` paths |
| 13 | iOS build overall | `pod install` and run on an iPhone; Xcode reports any selector typos | `QringSdkPlugin.m`, `qring_sdk.podspec` |
| 14 | Reconnect after going out of range, or after Bluetooth toggles | The state returns to connected within about 60 s | `AppState._scheduleRetry` |
| 15 | Battery life text ("about N days left") | Compare with real drain | `DeviceScreen` uses a 7.3-day design target |

### Recording results

For each test session:
1. Open Diagnostics and copy the log.
2. Save it, named by date and phone model.
3. Note which rows above passed.
4. Fix any failing row in the place listed, then re-run that row.

---

## 12. Known limitations (SDK or firmware, not app bugs)

- **No light-sleep smart wake.** The band alarm fires at the end of your window; the phone backup sounds 5 minutes later.
- **No breathing rate** and **no heart-rate broadcast** to gym equipment in the SDK.
- **Haptic strength** is approximated by pulse duration.
- **App-side cues** (goal, breathe, battery) need the app running in the foreground or recently backgrounded. Band-side cues (alarm, move) work with the app closed.
- **The iOS Simulator** cannot run ring features.

---

## 13. Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not find com.oudmon:qring-sdk` | Add the `libs-maven` repo to the app's `android/build.gradle.kts` (already done here) |
| `Failed to find target … android-37` | Keep the `permission_handler_android: ^13.0.1` override in `pubspec.yaml` |
| `Could not close incremental caches` (Windows) | `kotlin.incremental=false` in `android/gradle.properties` (already set) |
| `Could not determine java version` | Install JDK 17+, then run `flutter config --jdk-dir=…` |
| iOS link error "building for iOS Simulator" | Run on a physical iPhone. The podspec already skips the SDK on the Simulator |
| No band found | Bluetooth on, permissions granted, band charged and awake, not connected to another phone or the vendor app |
| Screens show sample data after pairing | Pull to refresh on Today, or Diagnostics › *Sync now*. Check the event log for `fail` lines |
