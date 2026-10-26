import 'dart:math' as math;

import 'package:qring_sdk/qring_sdk.dart';

import 'haptics.dart';
import 'models.dart';

/// Plausible sample data so every screen can be reviewed without a ring
/// (and in the iOS Simulator, which the vendor SDK cannot run on).
abstract final class DemoData {
  static DateTime _day(int ago) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).subtract(Duration(days: ago));
  }

  static DayRecord day(int ago) {
    final rnd = math.Random(ago * 7919 + 13);
    final date = _day(ago);
    final d = DayRecord(date);

    // Night: ~22:48 → 06:52 with stage blocks.
    final bed = date.subtract(Duration(minutes: 72 + rnd.nextInt(40)));
    const stages = [
      (SleepStage.light, 12), (SleepStage.deep, 48), (SleepStage.light, 34), (SleepStage.rem, 18),
      (SleepStage.light, 26), (SleepStage.deep, 40), (SleepStage.light, 44), (SleepStage.awake, 4),
      (SleepStage.light, 30), (SleepStage.rem, 42), (SleepStage.light, 34), (SleepStage.rem, 34),
      (SleepStage.light, 28), (SleepStage.deep, 10), (SleepStage.rem, 26), (SleepStage.light, 34),
    ];
    var t = bed;
    final segs = <SleepSegment>[];
    for (final (stage, min) in stages) {
      final len = Duration(minutes: (min * (0.85 + rnd.nextDouble() * 0.3)).round());
      segs.add(SleepSegment(t, t.add(len), stage));
      t = t.add(len);
    }
    int mins(SleepStage s) => segs.where((x) => x.stage == s).fold(0, (a, x) => a + x.duration.inMinutes);
    d.sleep = SleepNight(
      start: bed,
      end: t,
      totalMinutes: mins(SleepStage.deep) + mins(SleepStage.light) + mins(SleepStage.rem),
      deepMinutes: mins(SleepStage.deep),
      lightMinutes: mins(SleepStage.light),
      remMinutes: mins(SleepStage.rem),
      awakeMinutes: mins(SleepStage.awake),
      score: 0,
      segments: segs,
    );

    // Heart rate every 5 min from midnight until now (or end of day).
    final end = ago == 0 ? DateTime.now() : date.add(const Duration(days: 1));
    for (var m = 0; date.add(Duration(minutes: m)).isBefore(end); m += 5) {
      final at = date.add(Duration(minutes: m));
      final h = at.hour + at.minute / 60;
      final asleep = h < 7;
      final base = asleep ? 52 + rnd.nextInt(6) : 64 + 14 * math.sin((h - 7) / 14 * math.pi) + rnd.nextInt(8);
      final spike = (h > 11.6 && h < 12.4) ? 55.0 : 0.0;
      d.heartRate.add(Sample(at, (base + spike).toDouble()));
      if (asleep && m % 30 == 0) {
        d.hrv.add(Sample(at, 55 + rnd.nextInt(16).toDouble() - ago % 3));
        d.spo2.add(Sample(at, 96 + rnd.nextInt(3).toDouble()));
        d.temperature.add(Sample(at, 33.6 + rnd.nextDouble() * 0.3 + (ago == 0 ? 0.2 : 0)));
      }
    }
    d.respiratoryRate = 14 + rnd.nextDouble() * 0.6;
    final steps = ago == 0 ? 5620 : 6000 + rnd.nextInt(5500);
    d.activity = ActivitySummary(steps: steps, distanceMeters: (steps * 0.73).round(), kcal: steps * 0.073, activeMinutes: steps ~/ 148);
    return d;
  }

  static List<NightSummary> history(int nights, NightSummary Function(DayRecord) summarize) => [
        for (var i = nights - 1; i >= 0; i--) summarize(day(i)),
      ];

  static List<RecordedWorkout> workouts() => [
        RecordedWorkout(
          kind: WorkoutKind.run,
          start: _day(1).add(const Duration(hours: 7, minutes: 5)),
          duration: const Duration(minutes: 42, seconds: 10),
          distanceM: 8200,
          kcal: 512,
          avgHr: 148,
          maxHr: 171,
          zoneMinutes: {5: 2, 4: 11, 3: 22, 2: 6},
          cues: [
            WorkoutCue(const Duration(minutes: 6, seconds: 12), HapticPattern.onePulse, 'In your zone'),
            WorkoutCue(const Duration(minutes: 40, seconds: 54), HapticPattern.twoPulses, 'Goal reached · 8 km'),
          ],
          startedByTap: true,
        ),
        RecordedWorkout(
          kind: WorkoutKind.poolSwim,
          start: _day(2).add(const Duration(hours: 18)),
          duration: const Duration(minutes: 34, seconds: 5),
          activeDuration: const Duration(minutes: 31, seconds: 40),
          kcal: 296,
          startedByTap: true,
          endedByTap: true,
        ),
      ];
}
