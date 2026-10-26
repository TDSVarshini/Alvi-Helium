# Plug-and-play test checklist

Use this the first time Helium runs with a real band. Everything the band returns can be checked in **You › Diagnostics** (or **Your Helium › Diagnostics**). The copy icon puts the whole log on the clipboard, ready to paste into a bug report.

## 0. Install

- **Android:** `flutter run`, or install the APK:
  ```bash
  adb install -r build/app/outputs/flutter-apk/app-debug.apk
  ```
- **iOS:** on a Mac, run `cd ios && pod install`, open `Runner.xcworkspace`, set your signing team, and run on a physical iPhone. The Simulator only runs the app on sample data.

## 1. Pairing (onboarding steps 5–6)

| Check | Expected |
|---|---|
| Tap *I felt the pulse* | The phone asks for Bluetooth (and location on Android 11 and older) |
| Scan | Within about 8 s the strongest band shows as `HE-01-•••XXXX`, then *Connecting…* |
| Connected | The band buzzes short, long, short. *Yes, pair it* becomes active and firmware shows a version |
| *That's not my band* | Disconnects and searches again, skipping that band |

## 2. After pairing (automatic)

The Diagnostics event log should show `ok` for each of these steps:
- `sync time`
- `user profile`
- `step goal`
- `battery`
- `versions`
- `auto HR 10 min`, plus `auto SpO2`, `auto HRV`, `auto stress` and `auto temperature` for whatever the band supports
- `quiet hours`
- `move nudges`
- `silent alarm`

A `fail` line names the command. Note it and send the copied log.

## 3. Data (Diagnostics › *Read all history for day 0*, then day 1)

Compare each line with the vendor app on the same band:

| Line | What to verify |
|---|---|
| sleep | Start and end match the vendor app. Totals in minutes look right, not 60× too big or small |
| heart rate | Values 40–180. Times spread through the day |
| HRV | Typical 20–120 ms. If the values are 10× too big, HRV needs ÷10 |
| stress | Range 0–100 |
| SpO2 | Values 90–100 |
| temperature | About 30–37 °C |
| activity | Steps match the band. **kcal**: if 1000× too big, the band reports small calories |
| workouts | Start time is correct in your time zone. iOS applies a UTC+8 shift the vendor demo uses |

## 4. Live features

| Feature | How to test | Expected |
|---|---|---|
| Spot heart rate | Heart tab › tap the big number | Spinner, then a reading in about 30 s (band snug) |
| Measure now | Diagnostics › *heartRate / spo2 / hrv / stress / temperature / bloodPressure* | A value, or a clear error such as "not worn" |
| Live HR | Diagnostics › *Live HR* | A bpm line every 2 s on Android, and on each push on iOS |
| Haptics | Onboarding step 8 or Haptics › tap a row | Each pattern is felt on the band |
| Find my band | Your Helium › Find my band | The band pulses |
| Double-tap | Double-tap the core on any tab | Outdoor run recording opens. Double-tap again ends it and saves the summary |
| Workout | Activity › Start workout › Run | Timer, GPS distance and pace. With a ring that supports it, heart rate and zone cues |
| Steps live | Walk with the app open | The Activity count rises without a manual sync |
| Silent alarm | Sleep › Silent alarm › set window › Save | Diagnostics › *Read alarms* shows the window end time and days |
| Phone backup | Turn on *Phone sound backup* | A notification sounds 5 minutes after the window ends |
| Quiet hours | Haptics › Quiet hours | No app cues inside the window, and the band's do-not-disturb is set |
| Reconnect | Walk out of range, then come back with the app open | The state goes from OFFLINE back to connected within about a minute |
| Firmware | Your Helium › Firmware › choose a vendor `.bin` (battery 30%+) | Progress reaches 100%, the band restarts and reconnects |

## 5. Known limits (by design of the current SDK and firmware)

- **Smart wake:** the band has no light-sleep wake, so it wakes you at the end of your window.
- **Breathing rate and gym heart-rate broadcast:** not provided by the SDK.
- **Haptic strength:** Soft, Medium and Strong change pulse length, because the motor has one amplitude.
- **Background cues:** goal-reached, breathing-break and battery-low cues come from the app, so they only fire while the app is running.
- **No account or cloud:** data lives on the phone. Test **You › Privacy and data**:
  - **Export:** the share sheet opens with a `.json` file.
  - **Restore on a second phone, or after Delete all data:** the profile, settings, band and history come back.
  - **Delete all data:** returns to Welcome, with the band unpaired.
