/// Flutter wrapper for the QC Wireless smart-ring SDK
/// (Android `qring_sdk_1.0.0.60.aar`, iOS `QCBandSDK.framework`).
///
/// One [MethodChannel] carries commands and one [EventChannel] carries
/// everything the ring pushes. History queries take a `day` index:
/// 0 = today, 1 = yesterday … 6 (rings keep about seven days).
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'src/models.dart';

export 'src/models.dart';

class QRing {
  QRing._();
  static final QRing instance = QRing._();

  static const _methods = MethodChannel('qring_sdk/methods');
  static const _events = EventChannel('qring_sdk/events');

  /// Every push exactly as the native side sent it (useful for diagnostics).
  late final Stream<Map> rawEvents =
      _events.receiveBroadcastStream().map((e) => e as Map).asBroadcastStream();

  late final Stream<RingEvent> events =
      rawEvents.map(parseRingEvent).where((e) => e != null).cast<RingEvent>().asBroadcastStream();

  Stream<RingConnectionState> get connectionState =>
      events.whereType<ConnectionEvent>().map((e) => e.state);

  Stream<ScannedRing> get scanResults =>
      events.whereType<ScanResultEvent>().map((e) => e.ring);

  Stream<int> get realtimeHeartRate =>
      events.whereType<RealtimeHeartRateEvent>().map((e) => e.bpm);

  Stream<TouchGesture> get touches => events.whereType<TouchEvent>().map((e) => e.gesture);

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) =>
      _methods.invokeMethod<T>(method, args);

  Future<List<Map>> _list(String method, Map<String, Object?> args) async =>
      ((await _call<List>(method, args)) ?? const []).cast<Map>();

  // ── Connection ──────────────────────────────────────────────────────────

  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) =>
      _call('startScan', {'timeoutMs': timeout.inMilliseconds});

  Future<void> stopScan() => _call('stopScan');

  /// Connects to [id] from [ScannedRing.id]. Progress arrives on
  /// [connectionState]; commands are accepted once it reports `ready`.
  Future<void> connect(String id) => _call('connect', {'id': id});

  Future<void> disconnect() => _call('disconnect');

  /// Disconnects and clears the ring's bond so it can pair elsewhere.
  Future<void> unbind() => _call('unbind');

  Future<bool> isConnected() async => (await _call<bool>('isConnected')) ?? false;

  // ── Device ──────────────────────────────────────────────────────────────

  /// Syncs the phone clock to the ring and returns what the ring supports.
  /// Call first after every `ready`.
  Future<RingFeatures> syncTime() async =>
      RingFeatures.fromMap(await _call<Map>('syncTime'));

  Future<BatteryInfo> getBattery() async =>
      BatteryInfo.fromMap((await _call<Map>('getBattery'))!);

  Future<RingVersions> getVersions() async =>
      RingVersions.fromMap((await _call<Map>('getVersions')) ?? const {});

  Future<void> setUserProfile({
    required bool male,
    required int age,
    required int heightCm,
    required int weightKg,
    bool metric = true,
    bool is24h = true,
  }) =>
      _call('setUserProfile', {
        'male': male,
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'metric': metric,
        'is24h': is24h,
      });

  Future<void> setGoals({required int steps, int kcal = 500, int distanceMeters = 8000}) =>
      _call('setGoals', {'steps': steps, 'kcal': kcal, 'distanceM': distanceMeters});

  /// Makes the ring pulse so the user can find it.
  Future<void> findDevice() => _call('findDevice');

  /// Plays a custom vibration: [cycles] repeats of [on] buzz then [off] rest.
  /// Durations are rounded to the ring's 100 ms resolution.
  Future<void> vibrate({
    int cycles = 1,
    Duration on = const Duration(milliseconds: 200),
    Duration off = const Duration(milliseconds: 200),
  }) =>
      _call('vibrate', {
        'cycles': cycles,
        'onMs': on.inMilliseconds,
        'offMs': off.inMilliseconds,
      });

  /// Routes taps on the ring to [touches] (tap, swipe, long press).
  Future<void> setTouchEvents(bool enabled) => _call('setTouchEvents', {'enabled': enabled});

  Future<void> setAutoMeasure(AutoMeasureMetric metric,
          {required bool enabled, int intervalMinutes = 30}) =>
      _call('setAutoMeasure',
          {'metric': metric.name, 'enabled': enabled, 'intervalMin': intervalMinutes});

  /// Writes the ring's (single) vibration alarm. [minuteOfDay] is minutes
  /// after midnight; [weekdays] uses DateTime.monday..sunday.
  Future<void> setAlarm({required bool enabled, required int minuteOfDay, required Set<int> weekdays}) =>
      _call('setAlarm', {'enabled': enabled, 'minute': minuteOfDay, 'days': weekdays.toList()});

  /// Alarms stored on the ring, as raw maps (for diagnostics).
  Future<List<Map>> getAlarms() async => ((await _call<List>('getAlarms')) ?? const []).cast<Map>();

  /// Do-not-disturb window: the ring stays silent between [startMinute] and [endMinute].
  Future<void> setDoNotDisturb({required bool enabled, required int startMinute, required int endMinute}) =>
      _call('setDoNotDisturb', {'enabled': enabled, 'start': startMinute, 'end': endMinute});

  /// Sedentary ("move") reminder between [startMinute] and [endMinute].
  Future<void> setSedentaryReminder({
    required bool enabled,
    int startMinute = 9 * 60,
    int endMinute = 21 * 60,
    int intervalMinutes = 60,
    Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
  }) =>
      _call('setSedentaryReminder', {
        'enabled': enabled,
        'start': startMinute,
        'end': endMinute,
        'intervalMin': intervalMinutes,
        'days': weekdays.toList(),
      });

  Future<void> factoryReset() => _call('factoryReset');

  /// Flashes the firmware file at [filePath] (a local `.bin`). Progress
  /// arrives as [OtaProgressEvent]s; the ring reboots when done.
  Future<void> startOta(String filePath) => _call('startOta', {'path': filePath});

  // ── History ─────────────────────────────────────────────────────────────

  Future<ActivitySummary> getActivitySummary(int day) async =>
      ActivitySummary.fromMap((await _call<Map>('getActivitySummary', {'day': day})) ?? const {});

  Future<List<ActivitySlot>> getActivityDetail(int day) async =>
      [for (final m in await _list('getActivityDetail', {'day': day})) ActivitySlot.fromMap(m)];

  Future<List<Sample>> getHeartRate(int day) => _samples('getHeartRate', day);
  Future<List<Sample>> getSpO2(int day) => _samples('getSpO2', day);
  Future<List<Sample>> getHrv(int day) => _samples('getHrv', day);
  Future<List<Sample>> getStress(int day) => _samples('getStress', day);
  Future<List<Sample>> getTemperature(int day) => _samples('getTemperature', day);

  Future<List<Sample>> _samples(String method, int day) async =>
      [for (final m in await _list(method, {'day': day})) Sample.fromMap(m)]
        ..sort((a, b) => a.time.compareTo(b.time));

  Future<List<BloodPressureSample>> getBloodPressure(int day) async => [
        for (final m in await _list('getBloodPressure', {'day': day}))
          BloodPressureSample.fromMap(m)
      ];

  /// The main sleep that ended on [day], or null when none was recorded.
  Future<SleepNight?> getSleep(int day) async {
    final m = await _call<Map>('getSleep', {'day': day});
    return m == null ? null : SleepNight.fromMap(m);
  }

  Future<List<WorkoutRecord>> getWorkouts(int day) async =>
      [for (final m in await _list('getWorkouts', {'day': day})) WorkoutRecord.fromMap(m)];

  // ── Live measurement ────────────────────────────────────────────────────

  /// Runs one on-demand measurement. Intermediate values arrive as
  /// [MeasurementProgressEvent]s; the future completes with the final one.
  Future<MeasurementResult> measure(MeasurementType type,
      {Duration timeout = const Duration(seconds: 45)}) async {
    final m = (await _call<Map>(
        'measure', {'type': type.name, 'timeoutSec': timeout.inSeconds}))!;
    return MeasurementResult(type, (m['value'] as num?)?.toDouble() ?? 0,
        systolic: (m['sys'] as num?)?.toInt(), diastolic: (m['dia'] as num?)?.toInt());
  }

  Future<void> cancelMeasure(MeasurementType type) => _call('cancelMeasure', {'type': type.name});

  Future<void> startRealtimeHeartRate() => _call('startRealtimeHeartRate');
  Future<void> stopRealtimeHeartRate() => _call('stopRealtimeHeartRate');

  /// Starts/pauses/resumes/stops a workout on the ring. [sportType] uses the
  /// vendor codes (7 = outdoor run). Live data arrives as [WorkoutEvent]s.
  Future<void> workout(WorkoutAction action, {int sportType = 7}) =>
      _call('workout', {'action': action.name, 'type': sportType});
}

extension<T> on Stream<T> {
  Stream<S> whereType<S>() => where((e) => e is S).cast<S>();
}
