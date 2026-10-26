import 'package:alvi_helium/domain/insights.dart';
import 'package:alvi_helium/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qring_sdk/qring_sdk.dart';

void main() {
  test('sleep score rewards a full night with healthy deep and REM', () {
    final start = DateTime(2026, 10, 13, 22, 48);
    final night = SleepNight(
      start: start,
      end: start.add(const Duration(hours: 8)),
      totalMinutes: 462,
      deepMinutes: 98,
      lightMinutes: 252,
      remMinutes: 112,
      awakeMinutes: 6,
      score: 0,
      segments: const [],
    );
    expect(Insights.sleepScore(night), greaterThan(85));
  });

  test('readiness rises when HRV beats the baseline', () {
    final history = [
      for (var i = 10; i > 0; i--)
        NightSummary(date: DateTime(2026, 10, 14 - i), sleepMin: 450, sleepScore: 80, hrv: 55, restingHr: 56, steps: 8000, temp: 33.6),
    ];
    NightSummary night(double hrv) =>
        NightSummary(date: DateTime(2026, 10, 14), sleepMin: 460, sleepScore: 84, hrv: hrv, restingHr: 54, steps: 5000, temp: 33.8);
    final good = Insights.readiness(night(64), history).score;
    final poor = Insights.readiness(night(44), history).score;
    expect(good, greaterThan(poor));
    expect(good, inInclusiveRange(70, 100));
  });
}
