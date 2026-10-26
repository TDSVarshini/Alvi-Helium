import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:qring_sdk/qring_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/demo_data.dart';
import '../domain/insights.dart';
import '../domain/models.dart';

/// Health data: detailed records for recent days (from the ring, in memory)
/// plus persisted nightly summaries that baselines and trends are built on.
class HealthStore extends ChangeNotifier {
  HealthStore(this._prefs);
  final SharedPreferences _prefs;

  static const _historyKey = 'health.history';
  static const _workoutsKey = 'health.workouts';

  final Map<int, DayRecord> _days = {};
  List<NightSummary> history = [];
  List<RecordedWorkout> _recorded = [];
  final List<RecordedWorkout> _ringWorkouts = [];
  bool syncing = false;
  bool demo = false;
  DateTime? lastSync;

  DayRecord? day(int ago) => _days[ago];
  DayRecord? get today => _days[0];

  List<RecordedWorkout> get workouts {
    final all = [..._recorded];
    for (final r in _ringWorkouts) {
      // App-recorded workouts also exist on the ring; keep the richer copy.
      if (!all.any((w) => (w.start.difference(r.start)).inMinutes.abs() < 3)) all.add(r);
    }
    return all..sort((a, b) => b.start.compareTo(a.start));
  }

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime dateOf(int ago) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).subtract(Duration(days: ago));
  }

  NightSummary? summaryFor(DateTime date) =>
      history.where((n) => sameDay(n.date, date)).firstOrNull;

  NightSummary? get lastNight => summaryFor(dateOf(0));

  Readiness? get readiness {
    final n = lastNight;
    return n == null ? null : Insights.readiness(n, history);
  }

  /// Nights of the past [count] days ending today, oldest first (nulls when unworn).
  List<NightSummary?> recent(int count) => [for (var i = count - 1; i >= 0; i--) summaryFor(dateOf(i))];

  void load() {
    final h = _prefs.getString(_historyKey);
    if (h != null) {
      history = [for (final j in jsonDecode(h) as List) NightSummary.fromJson((j as Map).cast())];
    }
    final w = _prefs.getString(_workoutsKey);
    if (w != null) {
      _recorded = [for (final j in jsonDecode(w) as List) RecordedWorkout.fromJson((j as Map).cast())];
    }
    // Recent day details, so screens have content before the first sync.
    final d = _prefs.getString(_daysKey);
    if (d != null) {
      try {
        for (final j in jsonDecode(d) as List) {
          final day = _dayFromJson((j as Map).cast());
          final ago = dateOf(0).difference(day.date).inHours ~/ 24;
          if (ago >= 0 && ago < 7) _days[ago] = day;
        }
      } catch (e) {
        debugPrint('day cache: $e');
      }
    }
  }

  static const _daysKey = 'health.days';

  /// Everything this store keeps, for a backup file.
  Map<String, Object?> toBackup() => {
        'history': history.map((n) => n.toJson()).toList(),
        'workouts': _recorded.map((w) => w.toJson()).toList(),
        'days': _days.values.map(_dayToJson).toList(),
      };

  /// Replaces local data with a backup made by [toBackup].
  Future<void> restoreBackup(Map<String, Object?> b) async {
    demo = false;
    _days.clear();
    history = [for (final j in (b['history'] as List? ?? const [])) NightSummary.fromJson((j as Map).cast())];
    _recorded = [for (final j in (b['workouts'] as List? ?? const [])) RecordedWorkout.fromJson((j as Map).cast())];
    for (final j in (b['days'] as List? ?? const [])) {
      final day = _dayFromJson((j as Map).cast());
      final ago = dateOf(0).difference(day.date).inHours ~/ 24;
      if (ago >= 0 && ago < 7) _days[ago] = day;
    }
    await _persist();
    notifyListeners();
  }

  /// Deletes every health record on this phone.
  Future<void> eraseAll() async {
    _days.clear();
    history = [];
    _recorded = [];
    _ringWorkouts.clear();
    await _prefs.remove(_historyKey);
    await _prefs.remove(_workoutsKey);
    await _prefs.remove(_daysKey);
    notifyListeners();
  }

  static Map<String, Object?> _s(Sample s) => {'t': s.time.millisecondsSinceEpoch, 'v': s.value};
  static Sample _sFrom(Object? j) =>
      Sample(DateTime.fromMillisecondsSinceEpoch((j as Map)['t'] as int), (j['v'] as num).toDouble());
  static List<Sample> _list(Object? j) => [for (final x in (j as List? ?? const [])) _sFrom(x)];

  static Map<String, Object?> _dayToJson(DayRecord d) => {
        'date': d.date.toIso8601String(),
        'hr': d.heartRate.map(_s).toList(),
        'hrv': d.hrv.map(_s).toList(),
        'spo2': d.spo2.map(_s).toList(),
        'temp': d.temperature.map(_s).toList(),
        'stress': d.stress.map(_s).toList(),
        'resp': d.respiratoryRate,
        if (d.activity != null)
          'act': {
            'steps': d.activity!.steps,
            'distanceM': d.activity!.distanceMeters,
            'kcal': d.activity!.kcal,
            'activeMin': d.activity!.activeMinutes,
          },
        if (d.sleep != null)
          'sleep': {
            'start': d.sleep!.start.millisecondsSinceEpoch,
            'end': d.sleep!.end.millisecondsSinceEpoch,
            'totalMin': d.sleep!.totalMinutes,
            'deepMin': d.sleep!.deepMinutes,
            'lightMin': d.sleep!.lightMinutes,
            'remMin': d.sleep!.remMinutes,
            'awakeMin': d.sleep!.awakeMinutes,
            'score': d.sleep!.score,
            'segments': [
              for (final s in d.sleep!.segments)
                {'start': s.start.millisecondsSinceEpoch, 'end': s.end.millisecondsSinceEpoch, 'stage': s.stage.name}
            ],
          },
      };

  static DayRecord _dayFromJson(Map<String, Object?> j) {
    final d = DayRecord(DateTime.parse(j['date'] as String))
      ..heartRate = _list(j['hr'])
      ..hrv = _list(j['hrv'])
      ..spo2 = _list(j['spo2'])
      ..temperature = _list(j['temp'])
      ..stress = _list(j['stress'])
      ..respiratoryRate = (j['resp'] as num?)?.toDouble();
    if (j['act'] is Map) d.activity = ActivitySummary.fromMap(j['act'] as Map);
    if (j['sleep'] is Map) d.sleep = SleepNight.fromMap(j['sleep'] as Map);
    return d;
  }

  Future<void> _persist() async {
    history.sort((a, b) => a.date.compareTo(b.date));
    if (history.length > 120) history = history.sublist(history.length - 120);
    await _prefs.setString(_historyKey, jsonEncode(history.map((n) => n.toJson()).toList()));
    await _prefs.setString(_workoutsKey, jsonEncode(_recorded.map((w) => w.toJson()).toList()));
    if (!demo) await _prefs.setString(_daysKey, jsonEncode(_days.values.map(_dayToJson).toList()));
  }

  void loadDemo() {
    demo = true;
    _days.clear();
    for (var i = 0; i < 7; i++) {
      _days[i] = DemoData.day(i);
    }
    history = DemoData.history(42, Insights.summarize);
    _scoreHistory();
    _recorded = DemoData.workouts();
    lastSync = DateTime.now();
    notifyListeners();
  }

  void leaveDemo() {
    if (!demo) return;
    demo = false;
    _days.clear();
    history = [];
    _recorded = [];
    load();
    notifyListeners();
  }

  Future<void> addWorkout(RecordedWorkout w) async {
    _recorded.add(w);
    if (!demo) await _persist();
    notifyListeners();
  }

  void _scoreHistory() {
    history.sort((a, b) => a.date.compareTo(b.date));
    for (final n in history) {
      n.readiness = Insights.readiness(n, history).score;
    }
  }

  /// Pulls the last week from the ring. Today is always refreshed; earlier
  /// days only when we have no summary for them yet.
  Future<void> sync(QRing ring, RingFeatures features) async {
    if (syncing || demo) return;
    syncing = true;
    notifyListeners();
    try {
      for (var ago = 0; ago < 7; ago++) {
        if (ago > 0 && summaryFor(dateOf(ago)) != null && _days.containsKey(ago)) continue;
        final d = await _fetchDay(ring, features, ago);
        _days[ago] = d;
        history.removeWhere((n) => sameDay(n.date, d.date));
        history.add(Insights.summarize(d));
        if (ago == 0) notifyListeners(); // show today as soon as it lands
      }
      _scoreHistory();
      lastSync = DateTime.now();
      await _persist();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<DayRecord> _fetchDay(QRing ring, RingFeatures f, int ago) async {
    final d = DayRecord(dateOf(ago));
    Future<T?> attempt<T>(Future<T> Function() call) async {
      try {
        return await call();
      } catch (e) {
        debugPrint('ring sync day $ago: $e');
        return null;
      }
    }

    d.sleep = await attempt<SleepNight?>(() => ring.getSleep(ago));
    d.heartRate = await attempt(() => ring.getHeartRate(ago)) ?? [];
    if (f.hrv) d.hrv = await attempt(() => ring.getHrv(ago)) ?? [];
    if (f.spo2) d.spo2 = await attempt(() => ring.getSpO2(ago)) ?? [];
    if (f.temperature) d.temperature = await attempt(() => ring.getTemperature(ago)) ?? [];
    if (f.stress) d.stress = await attempt(() => ring.getStress(ago)) ?? [];
    d.activity = await attempt(() => ring.getActivitySummary(ago));
    final ws = await attempt(() => ring.getWorkouts(ago)) ?? [];
    for (final w in ws) {
      if (!_ringWorkouts.any((x) => x.start == w.start)) _ringWorkouts.add(RecordedWorkout.fromRing(w));
    }
    return d;
  }

  /// A spot heart-rate reading taken from the Heart tab.
  void addLiveHeartRate(double bpm) {
    final d = _days[0];
    if (d == null) return;
    d.heartRate.add(Sample(DateTime.now(), bpm));
    notifyListeners();
  }

  /// Live step counts pushed by the ring.
  void updateTodaySteps(int steps, int distanceM, double kcal) {
    final d = _days[0];
    if (d == null || demo) return;
    final prev = d.activity;
    d.activity = ActivitySummary(
        steps: steps, distanceMeters: distanceM, kcal: kcal, activeMinutes: prev?.activeMinutes ?? 0);
    notifyListeners();
  }
}
