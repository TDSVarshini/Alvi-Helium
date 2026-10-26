/// Plain data types returned by [QRing]. Every timestamp is a local
/// [DateTime]; native sides send milliseconds since epoch.
library;

DateTime _ts(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch((v as num?)?.toInt() ?? 0);
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

enum RingConnectionState { disconnected, connecting, connected, ready }

enum MeasurementType { heartRate, spo2, bloodPressure, hrv, stress, temperature }

enum SleepStage { awake, light, deep, rem, unknown }

enum TouchGesture { swipeDown, swipeUp, tap, longPress, unknown }

enum WorkoutAction { start, pause, resume, stop }

enum AutoMeasureMetric { heartRate, spo2, hrv, stress, temperature }

class ScannedRing {
  ScannedRing({required this.id, required this.name, required this.rssi, this.mac});

  /// Connect key: MAC address on Android, CoreBluetooth identifier on iOS.
  final String id;
  final String name;
  final int rssi;

  /// MAC address when known (iOS derives it from advertisement data).
  final String? mac;

  factory ScannedRing.fromMap(Map m) => ScannedRing(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        rssi: _i(m['rssi']),
        mac: m['mac'] as String?,
      );
}

class RingFeatures {
  RingFeatures(this.raw);
  final Map<String, bool> raw;

  bool get heartRate => raw['heartRate'] ?? true;
  bool get spo2 => raw['spo2'] ?? false;
  bool get bloodPressure => raw['bloodPressure'] ?? false;
  bool get hrv => raw['hrv'] ?? false;
  bool get stress => raw['stress'] ?? false;
  bool get temperature => raw['temperature'] ?? false;
  bool get appMeasure => raw['appMeasure'] ?? false;
  bool get touch => raw['touch'] ?? false;

  factory RingFeatures.fromMap(Map? m) => RingFeatures({
        for (final e in (m ?? const {}).entries)
          e.key as String: e.value == true || e.value == 1,
      });
}

class BatteryInfo {
  BatteryInfo(this.level, this.charging);
  final int level;
  final bool charging;
  factory BatteryInfo.fromMap(Map m) => BatteryInfo(_i(m['level']), m['charging'] == true);
}

class RingVersions {
  RingVersions(this.firmware, this.hardware);
  final String firmware;
  final String hardware;
  factory RingVersions.fromMap(Map m) =>
      RingVersions((m['firmware'] as String?) ?? '', (m['hardware'] as String?) ?? '');
}

/// One timestamped reading (heart rate, SpO2, HRV, stress or temperature).
class Sample {
  Sample(this.time, this.value);
  final DateTime time;
  final double value;
  factory Sample.fromMap(Map m) => Sample(_ts(m['ts']), _d(m['value']));
}

class BloodPressureSample {
  BloodPressureSample(this.time, this.systolic, this.diastolic);
  final DateTime time;
  final int systolic;
  final int diastolic;
  factory BloodPressureSample.fromMap(Map m) =>
      BloodPressureSample(_ts(m['ts']), _i(m['sys']), _i(m['dia']));
}

class ActivitySummary {
  ActivitySummary({
    required this.steps,
    required this.distanceMeters,
    required this.kcal,
    required this.activeMinutes,
  });
  final int steps;
  final int distanceMeters;
  final double kcal;
  final int activeMinutes;
  factory ActivitySummary.fromMap(Map m) => ActivitySummary(
        steps: _i(m['steps']),
        distanceMeters: _i(m['distanceM']),
        kcal: _d(m['kcal']),
        activeMinutes: _i(m['activeMin']),
      );
}

class ActivitySlot {
  ActivitySlot(this.time, this.steps, this.distanceMeters, this.kcal);
  final DateTime time;
  final int steps;
  final int distanceMeters;
  final double kcal;
  factory ActivitySlot.fromMap(Map m) =>
      ActivitySlot(_ts(m['ts']), _i(m['steps']), _i(m['distanceM']), _d(m['kcal']));
}

class SleepSegment {
  SleepSegment(this.start, this.end, this.stage);
  final DateTime start;
  final DateTime end;
  final SleepStage stage;
  Duration get duration => end.difference(start);
  factory SleepSegment.fromMap(Map m) => SleepSegment(
        _ts(m['start']),
        _ts(m['end']),
        SleepStage.values.firstWhere((s) => s.name == m['stage'],
            orElse: () => SleepStage.unknown),
      );
}

class SleepNight {
  SleepNight({
    required this.start,
    required this.end,
    required this.totalMinutes,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    required this.score,
    required this.segments,
  });
  final DateTime start;
  final DateTime end;
  final int totalMinutes;
  final int deepMinutes;
  final int lightMinutes;
  final int remMinutes;
  final int awakeMinutes;

  /// 0 when the ring does not compute a score (the app derives one).
  final int score;
  final List<SleepSegment> segments;

  factory SleepNight.fromMap(Map m) => SleepNight(
        start: _ts(m['start']),
        end: _ts(m['end']),
        totalMinutes: _i(m['totalMin']),
        deepMinutes: _i(m['deepMin']),
        lightMinutes: _i(m['lightMin']),
        remMinutes: _i(m['remMin']),
        awakeMinutes: _i(m['awakeMin']),
        score: _i(m['score']),
        segments: [
          for (final s in (m['segments'] as List? ?? const [])) SleepSegment.fromMap(s as Map)
        ],
      );
}

class WorkoutRecord {
  WorkoutRecord({
    required this.type,
    required this.start,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.kcal,
    required this.avgHr,
    required this.minHr,
    required this.maxHr,
    required this.steps,
  });

  /// Vendor sport type code (4 walk, 7 run, 9 cycling, ...).
  final int type;
  final DateTime start;
  final int durationSeconds;
  final int distanceMeters;
  final double kcal;
  final int avgHr;
  final int minHr;
  final int maxHr;
  final int steps;

  factory WorkoutRecord.fromMap(Map m) => WorkoutRecord(
        type: _i(m['type']),
        start: _ts(m['start']),
        durationSeconds: _i(m['durationSec']),
        distanceMeters: _i(m['distanceM']),
        kcal: _d(m['kcal']),
        avgHr: _i(m['avgHr']),
        minHr: _i(m['minHr']),
        maxHr: _i(m['maxHr']),
        steps: _i(m['steps']),
      );
}

class MeasurementResult {
  MeasurementResult(this.type, this.value, {this.systolic, this.diastolic});
  final MeasurementType type;
  final double value;
  final int? systolic;
  final int? diastolic;
}

class LiveWorkout {
  LiveWorkout(this.durationSeconds, this.heartRate, this.steps, this.distanceMeters, this.kcal);
  final int durationSeconds;
  final int heartRate;
  final int steps;
  final int distanceMeters;
  final double kcal;
  factory LiveWorkout.fromMap(Map m) => LiveWorkout(_i(m['durationSec']), _i(m['heartRate']),
      _i(m['steps']), _i(m['distanceM']), _d(m['kcal']));
}

/// Everything pushed from the ring arrives as one of these.
sealed class RingEvent {
  const RingEvent();
}

class ScanResultEvent extends RingEvent {
  const ScanResultEvent(this.ring);
  final ScannedRing ring;
}

class ScanStoppedEvent extends RingEvent {
  const ScanStoppedEvent();
}

class ConnectionEvent extends RingEvent {
  const ConnectionEvent(this.state, this.id);
  final RingConnectionState state;
  final String? id;
}

class BatteryEvent extends RingEvent {
  const BatteryEvent(this.battery);
  final BatteryInfo battery;
}

class VersionsEvent extends RingEvent {
  const VersionsEvent(this.versions);
  final RingVersions versions;
}

class RealtimeHeartRateEvent extends RingEvent {
  const RealtimeHeartRateEvent(this.bpm);
  final int bpm;
}

class MeasurementProgressEvent extends RingEvent {
  const MeasurementProgressEvent(this.type, this.value);
  final MeasurementType type;
  final double value;
}

class WorkoutEvent extends RingEvent {
  const WorkoutEvent(this.data);
  final LiveWorkout data;
}

class TouchEvent extends RingEvent {
  const TouchEvent(this.gesture);
  final TouchGesture gesture;
}

/// The ring stored new data of [kind]; re-query history to pick it up.
class DataUpdatedEvent extends RingEvent {
  const DataUpdatedEvent(this.kind, {this.steps, this.distanceMeters, this.kcal});
  final String kind;

  /// Present when the ring pushed live totals with a `steps` update.
  final int? steps;
  final int? distanceMeters;
  final double? kcal;
}

class OtaProgressEvent extends RingEvent {
  const OtaProgressEvent(this.percent, {this.done = false, this.error});
  final int percent;
  final bool done;
  final String? error;
}

class BluetoothStateEvent extends RingEvent {
  const BluetoothStateEvent(this.poweredOn);
  final bool poweredOn;
}

RingEvent? parseRingEvent(Map m) {
  T byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);
  switch (m['event']) {
    case 'scanResult':
      return ScanResultEvent(ScannedRing.fromMap(m));
    case 'scanStopped':
      return const ScanStoppedEvent();
    case 'connection':
      return ConnectionEvent(
          byName(RingConnectionState.values, m['state'], RingConnectionState.disconnected),
          m['id'] as String?);
    case 'battery':
      return BatteryEvent(BatteryInfo.fromMap(m));
    case 'versions':
      return VersionsEvent(RingVersions.fromMap(m));
    case 'realtimeHeartRate':
      return RealtimeHeartRateEvent(_i(m['bpm']));
    case 'measurementProgress':
      return MeasurementProgressEvent(
          byName(MeasurementType.values, m['type'], MeasurementType.heartRate), _d(m['value']));
    case 'workout':
      return WorkoutEvent(LiveWorkout.fromMap(m));
    case 'touch':
      return TouchEvent(byName(TouchGesture.values, m['gesture'], TouchGesture.unknown));
    case 'dataUpdated':
      return DataUpdatedEvent((m['kind'] as String?) ?? 'unknown',
          steps: (m['steps'] as num?)?.toInt(),
          distanceMeters: (m['distanceM'] as num?)?.toInt(),
          kcal: (m['kcal'] as num?)?.toDouble());
    case 'ota':
      return OtaProgressEvent(_i(m['percent']), done: m['done'] == true, error: m['error'] as String?);
    case 'bluetooth':
      return BluetoothStateEvent(m['on'] == true);
  }
  return null;
}
