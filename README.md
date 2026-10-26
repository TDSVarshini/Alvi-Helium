# ALVI Helium (Flutter)

The ALVI Helium companion app for Android and iOS, built from the *ALVI Helium App* design. It talks to the QC Wireless band/ring hardware through `packages/qring_sdk`, a Flutter plugin that wraps both vendor SDKs.

```
alvi_helium/
├─ lib/                      the app
│  ├─ theme/tokens.dart      colours and type taken from the design
│  ├─ l10n.dart              English / French (inline t('en', 'fr'))
│  ├─ widgets/               shared UI, glyphs and chart painters
│  ├─ domain/                models, insights (readiness, sleep score), haptic patterns, sample data
│  ├─ state/                 AppState (pairing, connection), HealthStore (sync and cache), WorkoutSession
│  └─ screens/               onboarding (7 steps), Today, Sleep, Heart, Activity, You and their detail pages
└─ packages/qring_sdk/       Flutter plugin
   ├─ lib/                   Dart API (QRing.instance) and models
   ├─ android/               Kotlin bridge + vendor AAR in a local Maven repo (libs-maven/)
   └─ ios/                   Objective-C bridge + vendor QCBandSDK.framework (Frameworks/)
```

## Running

```bash
flutter pub get
flutter run            # on a phone, with Bluetooth on
```

- **Android:** minSdk 26, JDK 17+ (this machine: Temurin 17 in `C:\Users\ADMIN\jdk`, set via `flutter config --jdk-dir`). `flutter build apk --debug` succeeds. Build notes:
  - `android/build.gradle.kts` declares the plugin's local Maven repo (`packages/qring_sdk/android/libs-maven`). Any app using the plugin needs that line.
  - `pubspec.yaml` pins `permission_handler_android` to 13.x: 14.x needs compileSdk 37, which AGP 9.0 can't resolve yet.
  - `android/gradle.properties` sets `kotlin.incremental=false`. Kotlin's incremental caches break on Windows when the project and the pub cache are on different drives.
- **iOS:** run `pod install` in `ios/` on a Mac, then build to a physical iPhone. The vendor framework contains arm64 *device* code only:
  - On the Simulator the plugin compiles a stub, so the app runs on sample data.
  - Pairing and every ring feature need a real iPhone.

### Sample data

Without a paired band you can still see the whole app. Use *Explore with sample data* on the welcome screen, or finish onboarding without pairing. Either way the app fills every screen with plausible data, and pairing a band later replaces it.

## Plugin API (`package:qring_sdk`)

```dart
final ring = QRing.instance;
ring.events                       // every push from the ring (sealed RingEvent)
await ring.startScan(); ring.scanResults.listen(...);
await ring.connect(id);           // wait for ConnectionEvent(ready)
final features = await ring.syncTime();   // call first after each connect
await ring.getBattery(); await ring.getVersions();
await ring.getSleep(0);           // day index: 0 = today … 6
await ring.getHeartRate(0); getHrv / getSpO2 / getTemperature / getStress / getBloodPressure
await ring.getActivitySummary(0); getActivityDetail(0); getWorkouts(0)
await ring.measure(MeasurementType.heartRate);
await ring.startRealtimeHeartRate();  ring.realtimeHeartRate.listen(...)
await ring.vibrate(cycles: 2, on: Duration(milliseconds: 200), off: Duration(milliseconds: 200));
await ring.workout(WorkoutAction.start, sportType: 7);
await ring.setAutoMeasure(AutoMeasureMetric.heartRate, enabled: true, intervalMinutes: 10);
await ring.findDevice(); ring.factoryReset(); ring.startOta(path);
```

The two native sides implement one channel contract (`qring_sdk/methods` and `qring_sdk/events`). They also handle each SDK's quirks:

| | Android (AAR 1.0.0.60) | iOS (QCBandSDK 1.0.0.20260812) |
|---|---|---|
| Bluetooth owner | SDK (`BleOperateManager`) | Plugin owns `CBCentralManager`, then hands the peripheral to the SDK |
| Ready signal | `onServiceDiscovered` on the SDK's broadcast receiver | `addPeripheral:finished:` returns YES |
| Command concurrency | SDK queues commands | Plugin serialises commands (the SDK fails parallel calls with error 1001) |
| Timeouts | Plugin adds them (the SDK has none) | Plugin adds them |
| Ring id | MAC address | CoreBluetooth UUID (MAC parsed from the advertisement when present) |

## Known gaps and things to verify on hardware

These parts were built from the vendor docs and samples but have not yet run against a real band:

- **Units in history data.** The app has to guess some units:
  - Sleep segment timestamps may be seconds or milliseconds; the app detects which.
  - HRV and stress may be raw values or raw ÷ 10; the app currently shows the raw value.
  - Calories may be in kcal or in small calories (cal).

  Check each against the vendor app on the same band.
- **iOS workout start times.** The vendor demo shifts them by the UTC+8 offset, and the plugin copies that. Confirm it on a band used outside UTC+8.
- **Haptic strength.** The motor has one amplitude, so Soft, Medium and Strong change pulse length, not force.
- **Alarm and reminder week order.** Alarms, do-not-disturb and sedentary reminders use a Sunday-first week, as the iOS headers document. The Android bit layout is inferred from that; confirm with Diagnostics › *Read alarms*.
- **On every connect** the app pushes these to the band:
  - Auto-measure for heart rate, plus SpO2, HRV, stress and temperature if the band supports them
  - Quiet hours, as the band's do-not-disturb
  - Move nudges, as the band's sedentary reminder
  - The silent alarm, which fires at the end of the window because the band has no smart wake
- **App-side cues and backups:** goal reached, battery low and breathing breaks, plus the phone-sound alarm backup (a scheduled notification).
- **Not possible with this SDK:**
  - Light-sleep smart wake
  - Heart-rate broadcast to gym equipment
  - Breathing rate

**No account, no billing, no backend.** All data stays on the phone. Moving to a new phone uses a backup file (You › Privacy and data). See [HANDBOOK.md](HANDBOOK.md) for the full guide.

See [TESTING.md](TESTING.md) for the plug-and-play checklist.
- **Placeholders to replace:** Privacy officer `[CONTACT]` and `[PRICE CAD]` are copied from the design as-is.
