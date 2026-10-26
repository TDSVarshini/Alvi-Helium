import 'package:alvi_helium/domain/models.dart';
import 'package:alvi_helium/state/app_state.dart';
import 'package:alvi_helium/state/health_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _fresh() async {
  final prefs = await SharedPreferences.getInstance();
  return AppState(prefs, HealthStore(prefs))..load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a backup restores profile, settings and history on a new phone', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await _fresh();
    a.profile
      ..name = 'Sam'
      ..heightCm = 181;
    a.prefs.alarm = AlarmWindow(earliest: 400, latest: 430, days: {1, 3, 5});
    a.health.history = [
      NightSummary(date: DateTime(2026, 10, 20), sleepMin: 440, hrv: 58),
      NightSummary(date: DateTime(2026, 10, 21), sleepMin: 470, hrv: 61),
    ];
    final file = a.exportBackup();

    SharedPreferences.setMockInitialValues({});
    final b = await _fresh();
    await b.importBackup(file);
    expect(b.profile.name, 'Sam');
    expect(b.profile.heightCm, 181);
    expect(b.prefs.alarm.latest, 430);
    expect(b.prefs.alarm.days, {1, 3, 5});
    expect(b.onboarded, isTrue);
    expect(b.paired, isFalse);
    // Unpaired restores show sample data until a band is paired again.
    expect(b.health.demo, isTrue);
  });

  test('non-backup files are rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await _fresh();
    expect(() => a.importBackup('{"hello": 1}'), throwsFormatException);
  });
}
