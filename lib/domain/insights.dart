import 'dart:math' as math;

import 'package:qring_sdk/qring_sdk.dart';

import 'models.dart';

/// Turns raw ring data into the scores and sentences the app shows.
/// General wellness guidance only; nothing here is diagnostic.
abstract final class Insights {
  static double? mean(Iterable<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

  /// Samples recorded during the sleep window (or the whole day if no sleep).
  static List<double> nightly(List<Sample> s, SleepNight? sleep) {
    final inWindow = sleep == null
        ? s
        : s.where((x) => !x.time.isBefore(sleep.start) && !x.time.isAfter(sleep.end)).toList();
    return (inWindow.isEmpty ? s : inWindow).map((x) => x.value).toList();
  }

  static double? restingHr(DayRecord d) {
    final v = nightly(d.heartRate, d.sleep).where((x) => x >= 30).toList()..sort();
    if (v.isEmpty) return null;
    final low = v.take(math.max(1, v.length ~/ 10));
    return mean(low);
  }

  static int sleepScore(SleepNight n) {
    if (n.score > 0) return n.score;
    final total = math.max(1, n.totalMinutes);
    final duration = math.min(1.0, total / 480) * 50;
    final deep = math.min(1.0, n.deepMinutes / total / 0.18) * 20;
    final rem = math.min(1.0, n.remMinutes / total / 0.22) * 20;
    final calm = (10 - n.awakeMinutes / total * 100).clamp(0, 10);
    return (duration + deep + rem + calm).round().clamp(0, 100);
  }

  /// Builds the persisted nightly summary from a synced day.
  static NightSummary summarize(DayRecord d) => NightSummary(
        date: d.date,
        sleepMin: d.sleep?.totalMinutes ?? 0,
        deepMin: d.sleep?.deepMinutes ?? 0,
        remMin: d.sleep?.remMinutes ?? 0,
        sleepScore: d.sleep == null ? 0 : sleepScore(d.sleep!),
        hrv: mean(nightly(d.hrv, d.sleep)),
        restingHr: restingHr(d),
        spo2: mean(nightly(d.spo2, d.sleep).where((v) => v >= 80)),
        temp: mean(nightly(d.temperature, d.sleep).where((v) => v > 25)),
        respRate: d.respiratoryRate,
        steps: d.activity?.steps ?? 0,
      );

  /// Baseline = mean over up to 14 earlier nights that have a value.
  static double? baseline(List<NightSummary> history, DateTime before, double? Function(NightSummary) f) {
    final v = history
        .where((n) => n.date.isBefore(before))
        .map(f)
        .whereType<double>()
        .toList()
        .reversed
        .take(14);
    return mean(v);
  }

  static Readiness readiness(NightSummary night, List<NightSummary> history) {
    double clamp01(double v) => v.clamp(0.0, 1.0);
    final sleep = clamp01(night.sleepScore / 100);
    final hrvBase = baseline(history, night.date, (n) => n.hrv);
    final rhrBase = baseline(history, night.date, (n) => n.restingHr);
    final tempBase = baseline(history, night.date, (n) => n.temp);
    final stepsBase = baseline(history, night.date, (n) => n.steps > 0 ? n.steps.toDouble() : null);
    final yesterday = history.where((n) => n.date.isBefore(night.date)).lastOrNull;

    final hrv = (night.hrv != null && hrvBase != null) ? clamp01(0.6 + (night.hrv! / hrvBase - 1) * 2.5) : 0.6;
    final rhr = (night.restingHr != null && rhrBase != null) ? clamp01(0.65 + (rhrBase - night.restingHr!) / 12) : 0.65;
    final load = (yesterday != null && stepsBase != null && stepsBase > 0)
        ? clamp01(0.75 - (yesterday.steps / stepsBase - 1) * 0.5)
        : 0.6;
    final tempDev = (night.temp != null && tempBase != null) ? night.temp! - tempBase : 0.0;
    final temp = clamp01(1 - tempDev.abs() / 1.0);

    final score = (100 * (0.35 * sleep + 0.25 * hrv + 0.2 * rhr + 0.1 * load + 0.1 * temp)).round();
    return Readiness(
      score: night.worn ? score : 0,
      sleep: sleep,
      hrv: hrv,
      restingHr: rhr,
      load: load,
      temp: temp,
      hrvDelta: (night.hrv != null && hrvBase != null) ? night.hrv! - hrvBase : null,
      tempDelta: (night.temp != null && tempBase != null) ? tempDev : null,
    );
  }
}

class Readiness {
  Readiness({
    required this.score,
    required this.sleep,
    required this.hrv,
    required this.restingHr,
    required this.load,
    required this.temp,
    this.hrvDelta,
    this.tempDelta,
  });
  final int score;
  final double sleep, hrv, restingHr, load, temp; // 0..1 contributions
  final double? hrvDelta;
  final double? tempDelta;

  bool get hasData => score > 0;
}

/// Label for a 0..1 factor in the design's words.
String factorLabel(double f, {required bool french, bool hrv = false, bool temp = false}) {
  if (temp) return f >= 0.6 ? (french ? 'Normale' : 'Normal') : (french ? 'Élevée' : 'Shifted');
  if (f >= 0.85) return hrv ? (french ? 'Élevé' : 'High') : (french ? 'Bon' : 'Good');
  if (f >= 0.7) return french ? 'Bon' : 'Good';
  if (f >= 0.45) return french ? 'Moyen' : 'Fair';
  return french ? 'Faible' : 'Low';
}
