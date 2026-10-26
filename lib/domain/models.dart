import 'package:qring_sdk/qring_sdk.dart';

import 'haptics.dart';

enum Sex { female, male, unspecified }

enum Goal { sleep, recover, train, stress, move }

enum WearSpot { wrist, upperArm }

enum BandSize { s, m, l }

enum Hand { left, right }

class UserProfile {
  UserProfile({
    this.name = '',
    this.birthYear = 1992,
    this.heightCm = 175,
    this.weightKg = 70,
    this.sex = Sex.unspecified,
    Set<Goal>? goals,
    DateTime? memberSince,
  })  : goals = goals ?? {},
        memberSince = memberSince ?? DateTime.now();

  String name;
  int birthYear;
  int heightCm;
  int weightKg;
  Sex sex;
  Set<Goal> goals;
  DateTime memberSince;

  int get age => DateTime.now().year - birthYear;
  int get maxHr => 220 - age;

  Map<String, Object?> toJson() => {
        'name': name,
        'birthYear': birthYear,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'sex': sex.name,
        'goals': goals.map((g) => g.name).toList(),
        'memberSince': memberSince.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, Object?> j) => UserProfile(
        name: j['name'] as String? ?? '',
        birthYear: j['birthYear'] as int? ?? 1992,
        heightCm: j['heightCm'] as int? ?? 175,
        weightKg: j['weightKg'] as int? ?? 70,
        sex: Sex.values.asNameMap()[j['sex']] ?? Sex.unspecified,
        goals: {for (final g in (j['goals'] as List? ?? const [])) ?Goal.values.asNameMap()[g]},
        memberSince: DateTime.tryParse(j['memberSince'] as String? ?? ''),
      );
}

/// The smart-wake window. Stored in minutes after midnight.
class AlarmWindow {
  AlarmWindow({this.enabled = true, this.earliest = 390, this.latest = 420, Set<int>? days, this.phoneBackup = false})
      : days = days ?? {1, 2, 3, 4, 5};
  bool enabled;
  int earliest;
  int latest;
  Set<int> days; // DateTime.monday..sunday
  bool phoneBackup;

  Map<String, Object?> toJson() =>
      {'enabled': enabled, 'earliest': earliest, 'latest': latest, 'days': days.toList(), 'phoneBackup': phoneBackup};
  factory AlarmWindow.fromJson(Map<String, Object?> j) => AlarmWindow(
        enabled: j['enabled'] as bool? ?? true,
        earliest: j['earliest'] as int? ?? 390,
        latest: j['latest'] as int? ?? 420,
        days: {for (final d in (j['days'] as List? ?? const [1, 2, 3, 4, 5])) d as int},
        phoneBackup: j['phoneBackup'] as bool? ?? false,
      );
}

enum HapticCue { zone, goal, move, alarm, breathe }

class Prefs {
  Prefs();
  bool french = false;
  String region = 'Canada';
  bool metric = true;
  bool celsius = true;
  WearSpot wear = WearSpot.wrist;
  BandSize size = BandSize.m;
  Hand hand = Hand.left;
  HapticStrength strength = HapticStrength.medium;
  Map<HapticCue, bool> cues = {
    HapticCue.zone: true,
    HapticCue.goal: true,
    HapticCue.move: true,
    HapticCue.alarm: true,
    HapticCue.breathe: false,
  };
  int quietStart = 22 * 60;
  int quietEnd = 6 * 60 + 30;
  AlarmWindow alarm = AlarmWindow();
  int stepGoal = 10000;
  bool shareHeartRate = false;

  Map<String, Object?> toJson() => {
        'french': french,
        'region': region,
        'metric': metric,
        'celsius': celsius,
        'wear': wear.name,
        'size': size.name,
        'hand': hand.name,
        'strength': strength.name,
        'cues': {for (final e in cues.entries) e.key.name: e.value},
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'alarm': alarm.toJson(),
        'stepGoal': stepGoal,
        'shareHeartRate': shareHeartRate,
      };

  factory Prefs.fromJson(Map<String, Object?> j) {
    final p = Prefs()
      ..french = j['french'] as bool? ?? false
      ..region = j['region'] as String? ?? 'Canada'
      ..metric = j['metric'] as bool? ?? true
      ..celsius = j['celsius'] as bool? ?? true
      ..wear = WearSpot.values.asNameMap()[j['wear']] ?? WearSpot.wrist
      ..size = BandSize.values.asNameMap()[j['size']] ?? BandSize.m
      ..hand = Hand.values.asNameMap()[j['hand']] ?? Hand.left
      ..strength = HapticStrength.values.asNameMap()[j['strength']] ?? HapticStrength.medium
      ..quietStart = j['quietStart'] as int? ?? 22 * 60
      ..quietEnd = j['quietEnd'] as int? ?? 390
      ..stepGoal = j['stepGoal'] as int? ?? 10000
      ..shareHeartRate = j['shareHeartRate'] as bool? ?? false;
    final cues = j['cues'] as Map?;
    if (cues != null) {
      for (final c in HapticCue.values) {
        if (cues[c.name] is bool) p.cues[c] = cues[c.name] as bool;
      }
    }
    if (j['alarm'] is Map) p.alarm = AlarmWindow.fromJson((j['alarm'] as Map).cast());
    return p;
  }
}

/// Everything known about one calendar day (night that ended that morning,
/// plus that day's activity). Detailed series are kept only for recent days.
class DayRecord {
  DayRecord(this.date);
  final DateTime date;
  SleepNight? sleep;
  List<Sample> heartRate = [];
  List<Sample> hrv = [];
  List<Sample> spo2 = [];
  List<Sample> temperature = [];
  List<Sample> stress = [];
  ActivitySummary? activity;
  List<WorkoutRecord> ringWorkouts = [];
  double? respiratoryRate; // breaths/min when a source provides it
}

/// Compact per-night aggregates persisted for baselines and trends.
class NightSummary {
  NightSummary({
    required this.date,
    this.sleepMin = 0,
    this.deepMin = 0,
    this.remMin = 0,
    this.sleepScore = 0,
    this.hrv,
    this.restingHr,
    this.spo2,
    this.temp,
    this.respRate,
    this.steps = 0,
    this.readiness = 0,
  });
  final DateTime date;
  int sleepMin, deepMin, remMin, sleepScore, steps, readiness;
  double? hrv, restingHr, spo2, temp, respRate;

  bool get worn => sleepMin > 0;

  Map<String, Object?> toJson() => {
        'date': date.toIso8601String(),
        'sleepMin': sleepMin,
        'deepMin': deepMin,
        'remMin': remMin,
        'sleepScore': sleepScore,
        'hrv': hrv,
        'restingHr': restingHr,
        'spo2': spo2,
        'temp': temp,
        'respRate': respRate,
        'steps': steps,
        'readiness': readiness,
      };

  factory NightSummary.fromJson(Map<String, Object?> j) => NightSummary(
        date: DateTime.parse(j['date'] as String),
        sleepMin: j['sleepMin'] as int? ?? 0,
        deepMin: j['deepMin'] as int? ?? 0,
        remMin: j['remMin'] as int? ?? 0,
        sleepScore: j['sleepScore'] as int? ?? 0,
        hrv: (j['hrv'] as num?)?.toDouble(),
        restingHr: (j['restingHr'] as num?)?.toDouble(),
        spo2: (j['spo2'] as num?)?.toDouble(),
        temp: (j['temp'] as num?)?.toDouble(),
        respRate: (j['respRate'] as num?)?.toDouble(),
        steps: j['steps'] as int? ?? 0,
        readiness: j['readiness'] as int? ?? 0,
      );
}

enum WorkoutKind { run, walk, ride, poolSwim, strength }

extension WorkoutKindX on WorkoutKind {
  /// Vendor sport codes understood by the ring.
  int get ringCode => switch (this) {
        WorkoutKind.walk => 4,
        WorkoutKind.run => 7,
        WorkoutKind.ride => 9,
        WorkoutKind.poolSwim => 10,
        WorkoutKind.strength => 10,
      };
  bool get usesGps => this == WorkoutKind.run || this == WorkoutKind.walk || this == WorkoutKind.ride;
}

/// A cue the band gave during a workout ("In your zone" at 06:12).
class WorkoutCue {
  WorkoutCue(this.at, this.pattern, this.label);
  final Duration at;
  final HapticPattern pattern;
  final String label;
  Map<String, Object?> toJson() => {'at': at.inSeconds, 'pattern': pattern.name, 'label': label};
  factory WorkoutCue.fromJson(Map<String, Object?> j) => WorkoutCue(Duration(seconds: j['at'] as int),
      HapticPattern.values.asNameMap()[j['pattern']] ?? HapticPattern.onePulse, j['label'] as String? ?? '');
}

class RecordedWorkout {
  RecordedWorkout({
    required this.kind,
    required this.start,
    required this.duration,
    this.activeDuration,
    this.distanceM = 0,
    this.kcal = 0,
    this.avgHr = 0,
    this.maxHr = 0,
    Map<int, int>? zoneMinutes,
    List<WorkoutCue>? cues,
    this.startedByTap = false,
    this.endedByTap = false,
    this.fromRing = false,
  })  : zoneMinutes = zoneMinutes ?? {},
        cues = cues ?? [];

  final WorkoutKind kind;
  final DateTime start;
  final Duration duration;
  final Duration? activeDuration;
  final double distanceM;
  final double kcal;
  final int avgHr;
  final int maxHr;
  final Map<int, int> zoneMinutes;
  final List<WorkoutCue> cues;
  final bool startedByTap;
  final bool endedByTap;
  final bool fromRing;

  /// Sum of zone-minutes weighted by zone (a simple TRIMP-like load).
  double get effort =>
      zoneMinutes.entries.fold(0.0, (s, e) => s + e.key * e.value) / 10.0;

  Duration? get pacePerKm =>
      distanceM < 50 ? null : Duration(seconds: (duration.inSeconds / (distanceM / 1000)).round());

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'start': start.toIso8601String(),
        'duration': duration.inSeconds,
        'active': activeDuration?.inSeconds,
        'distanceM': distanceM,
        'kcal': kcal,
        'avgHr': avgHr,
        'maxHr': maxHr,
        'zones': {for (final e in zoneMinutes.entries) '${e.key}': e.value},
        'cues': cues.map((c) => c.toJson()).toList(),
        'startedByTap': startedByTap,
        'endedByTap': endedByTap,
      };

  factory RecordedWorkout.fromJson(Map<String, Object?> j) => RecordedWorkout(
        kind: WorkoutKind.values.asNameMap()[j['kind']] ?? WorkoutKind.run,
        start: DateTime.parse(j['start'] as String),
        duration: Duration(seconds: j['duration'] as int),
        activeDuration: j['active'] == null ? null : Duration(seconds: j['active'] as int),
        distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
        kcal: (j['kcal'] as num?)?.toDouble() ?? 0,
        avgHr: j['avgHr'] as int? ?? 0,
        maxHr: j['maxHr'] as int? ?? 0,
        zoneMinutes: {
          for (final e in ((j['zones'] as Map?) ?? const {}).entries) int.parse(e.key as String): e.value as int
        },
        cues: [for (final c in (j['cues'] as List? ?? const [])) WorkoutCue.fromJson((c as Map).cast())],
        startedByTap: j['startedByTap'] as bool? ?? false,
        endedByTap: j['endedByTap'] as bool? ?? false,
      );

  factory RecordedWorkout.fromRing(WorkoutRecord r) => RecordedWorkout(
        kind: switch (r.type) { 4 => WorkoutKind.walk, 9 => WorkoutKind.ride, _ => WorkoutKind.run },
        start: r.start,
        duration: Duration(seconds: r.durationSeconds),
        distanceM: r.distanceMeters.toDouble(),
        kcal: r.kcal,
        avgHr: r.avgHr,
        maxHr: r.maxHr,
        fromRing: true,
      );
}
