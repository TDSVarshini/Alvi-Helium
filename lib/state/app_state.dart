import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:qring_sdk/qring_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/haptics.dart';
import '../domain/models.dart';
import 'alarm_backup.dart';
import 'health_store.dart';
import 'permissions.dart';

/// User, preferences, pairing and the live ring connection.
class AppState extends ChangeNotifier {
  AppState(this._prefs, this.health, {QRing? ring}) : ring = ring ?? QRing.instance;

  final SharedPreferences _prefs;
  final HealthStore health;
  final QRing ring;

  UserProfile profile = UserProfile();
  Prefs prefs = Prefs();
  bool onboarded = false;
  String? deviceId;
  String? deviceName;
  String? deviceMac;

  RingConnectionState connection = RingConnectionState.disconnected;
  BatteryInfo? battery;
  RingVersions? versions;
  RingFeatures features = RingFeatures({});
  bool bluetoothOn = true;

  /// Last ring pushes and command outcomes, newest last (Diagnostics screen).
  final List<(DateTime, String)> log = [];

  final _doubleTaps = StreamController<void>.broadcast();

  /// The user double-tapped the core (two taps within 700 ms).
  Stream<void> get doubleTaps => _doubleTaps.stream;

  StreamSubscription<RingEvent>? _sub;
  StreamSubscription<Map>? _rawSub;
  DateTime? _lastTap;
  Timer? _resync;
  Timer? _retry;
  int _retryCount = 0;
  bool _foreground = true;
  bool _lowBatteryCued = false;
  DateTime? _lastBreathCue;

  bool get paired => deviceId != null;
  bool get ready => connection == RingConnectionState.ready;

  void load() {
    final p = _prefs.getString('profile');
    if (p != null) profile = UserProfile.fromJson((jsonDecode(p) as Map).cast());
    final s = _prefs.getString('prefs');
    if (s != null) prefs = Prefs.fromJson((jsonDecode(s) as Map).cast());
    onboarded = _prefs.getBool('onboarded') ?? false;
    deviceId = _prefs.getString('device.id');
    deviceName = _prefs.getString('device.name');
    deviceMac = _prefs.getString('device.mac');
    health.load();
    if (!paired && onboarded) health.loadDemo();
    _sub = ring.events.listen(_onEvent, onError: (Object e) => debugPrint('ring events: $e'));
    _rawSub = ring.rawEvents.listen((m) => note(m.toString()), onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rawSub?.cancel();
    _retry?.cancel();
    _resync?.cancel();
    _doubleTaps.close();
    super.dispose();
  }

  void note(String line) {
    log.add((DateTime.now(), line));
    if (log.length > 300) log.removeRange(0, log.length - 300);
  }

  Future<void> save() async {
    await _prefs.setString('profile', jsonEncode(profile.toJson()));
    await _prefs.setString('prefs', jsonEncode(prefs.toJson()));
    await _prefs.setBool('onboarded', onboarded);
    notifyListeners();
  }

  void setFrench(bool french) {
    prefs.french = french;
    save();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    if (!paired) health.loadDemo();
    await save();
  }

  /// Explore the app with sample data, no ring needed.
  Future<void> startDemo() async {
    profile.name = profile.name.isEmpty ? 'Sam' : profile.name;
    profile.memberSince = DateTime.now().subtract(const Duration(days: 42));
    onboarded = true;
    health.loadDemo();
    await save();
  }

  Future<void> rememberDevice(ScannedRing r) async {
    deviceId = r.id;
    deviceName = r.name;
    deviceMac = r.mac;
    await _prefs.setString('device.id', r.id);
    await _prefs.setString('device.name', r.name);
    if (r.mac != null) await _prefs.setString('device.mac', r.mac!);
    health.leaveDemo();
    notifyListeners();
    if (ready) {
      await applyRingSettings();
      unawaited(syncNow());
    }
  }

  // ── Backup (replaces a cloud account: everything lives on this phone) ──

  static const backupFormat = 'helium-backup';
  static const backupVersion = 1;

  /// Profile, settings, paired band and all health history as one JSON file.
  String exportBackup() => const JsonEncoder.withIndent(' ').convert({
        'format': backupFormat,
        'version': backupVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'profile': profile.toJson(),
        'prefs': prefs.toJson(),
        'device': {'id': deviceId, 'name': deviceName, 'mac': deviceMac},
        'health': health.toBackup(),
      });

  /// Restores a file made by [exportBackup]. Throws [FormatException] if it
  /// is not a Helium backup.
  Future<void> importBackup(String text) async {
    final j = jsonDecode(text);
    if (j is! Map || j['format'] != backupFormat) throw const FormatException('Not a Helium backup file');
    if ((j['version'] as int? ?? 0) > backupVersion) throw const FormatException('Backup is from a newer app version');
    profile = UserProfile.fromJson((j['profile'] as Map).cast());
    prefs = Prefs.fromJson((j['prefs'] as Map).cast());
    final d = (j['device'] as Map?) ?? const {};
    deviceId = d['id'] as String?;
    deviceName = d['name'] as String?;
    deviceMac = d['mac'] as String?;
    for (final (k, v) in [('device.id', deviceId), ('device.name', deviceName), ('device.mac', deviceMac)]) {
      v == null ? await _prefs.remove(k) : await _prefs.setString(k, v);
    }
    await health.restoreBackup(((j['health'] as Map?) ?? const {}).cast());
    if (!paired) health.loadDemo();
    onboarded = true;
    await save();
    note('backup restored (${health.history.length} nights)');
    unawaited(reconnect());
  }

  /// Unpairs and deletes every profile, setting and health record.
  Future<void> eraseEverything() async {
    if (paired) await unpair();
    await health.eraseAll();
    await _prefs.clear();
    profile = UserProfile();
    final french = prefs.french;
    prefs = Prefs()..french = french;
    onboarded = false;
    health.demo = false;
    await save();
  }

  // ── Connection ──────────────────────────────────────────────────────────

  Future<void> reconnect() async {
    if (!paired || connection != RingConnectionState.disconnected) return;
    if (!await ensureBluetoothPermissions()) return;
    note('connect → $deviceId');
    await ring.connect(deviceId!);
  }

  /// Foreground/background from the app lifecycle; retries only run in front.
  void setForeground(bool value) {
    _foreground = value;
    if (value) {
      ready ? syncNow() : reconnect();
    } else {
      _retry?.cancel();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!paired || !_foreground) return;
    // 5 s, 10 s, 20 s … capped at 60 s while the app is open.
    final delay = Duration(seconds: (5 * (1 << _retryCount.clamp(0, 4))).clamp(5, 60));
    _retryCount++;
    _retry = Timer(delay, () {
      if (connection == RingConnectionState.disconnected) reconnect();
    });
  }

  Future<void> unpair() async {
    _retry?.cancel();
    final id = deviceId;
    deviceId = deviceName = deviceMac = null;
    try {
      await ring.unbind();
    } catch (_) {}
    note('unpaired $id');
    battery = null;
    versions = null;
    await _prefs.remove('device.id');
    await _prefs.remove('device.name');
    await _prefs.remove('device.mac');
    health.loadDemo();
    notifyListeners();
  }

  // ── Ring settings ───────────────────────────────────────────────────────

  Future<void> _step(String what, Future<void> Function() f) async {
    try {
      await f();
      note('ok   $what');
    } catch (e) {
      note('fail $what: $e');
    }
  }

  /// Pushes everything the user configured to the ring. Safe to call often.
  Future<void> applyRingSettings() async {
    if (!ready) return;
    final f = features;
    await _step('auto HR 10 min', () => ring.setAutoMeasure(AutoMeasureMetric.heartRate, enabled: true, intervalMinutes: 10));
    if (f.spo2) await _step('auto SpO2', () => ring.setAutoMeasure(AutoMeasureMetric.spo2, enabled: true, intervalMinutes: 30));
    if (f.hrv) await _step('auto HRV', () => ring.setAutoMeasure(AutoMeasureMetric.hrv, enabled: true, intervalMinutes: 30));
    if (f.stress) await _step('auto stress', () => ring.setAutoMeasure(AutoMeasureMetric.stress, enabled: true, intervalMinutes: 30));
    if (f.temperature) {
      await _step('auto temperature', () => ring.setAutoMeasure(AutoMeasureMetric.temperature, enabled: true, intervalMinutes: 30));
    }
    await applyQuietHours();
    await applyMoveNudges();
    await applyAlarm();
  }

  Future<void> applyQuietHours() async {
    if (!ready) return;
    await _step('quiet hours', () => ring.setDoNotDisturb(enabled: true, startMinute: prefs.quietStart, endMinute: prefs.quietEnd));
  }

  Future<void> applyMoveNudges() async {
    if (!ready) return;
    await _step('move nudges', () => ring.setSedentaryReminder(enabled: prefs.cues[HapticCue.move]!, intervalMinutes: 60));
  }

  /// The ring has no light-sleep smart wake, so it vibrates at the end of the
  /// window as a guaranteed wake; the phone backup follows a few minutes later.
  Future<void> applyAlarm({String title = 'Time to wake', String body = 'Your silent alarm window has ended.'}) async {
    final a = prefs.alarm;
    final on = a.enabled && prefs.cues[HapticCue.alarm]!;
    if (ready) {
      await _step('silent alarm ${on ? a.latest : 'off'}',
          () => ring.setAlarm(enabled: on, minuteOfDay: a.latest, weekdays: a.days));
    }
    await AlarmBackup.apply(AlarmWindow(enabled: on, earliest: a.earliest, latest: a.latest, days: a.days, phoneBackup: a.phoneBackup),
        title: title, body: body);
  }

  // ── Haptics and cues ────────────────────────────────────────────────────

  bool get inQuietHours {
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    final s = prefs.quietStart, e = prefs.quietEnd;
    return s <= e ? (m >= s && m < e) : (m >= s || m < e);
  }

  Future<void> play(HapticPattern p) async {
    if (!ready) return;
    try {
      await p.play(ring, strength: prefs.strength);
    } catch (e) {
      debugPrint('haptic: $e');
    }
  }

  /// Background cues the app gives while it is running.
  void _checkCues() {
    final today = health.today;
    if (today == null || inQuietHours) return;
    final steps = today.activity?.steps ?? 0;
    final key = 'goal.${HealthStore.dateOf(0).toIso8601String().substring(0, 10)}';
    if (steps >= prefs.stepGoal && !(_prefs.getBool(key) ?? false) && prefs.cues[HapticCue.goal]!) {
      _prefs.setBool(key, true);
      play(HapticPattern.twoPulses);
      note('cue goal reached ($steps steps)');
    }
    final stress = today.stress.lastOrNull;
    if (stress != null &&
        prefs.cues[HapticCue.breathe]! &&
        stress.value >= 70 &&
        DateTime.now().difference(stress.time) < const Duration(minutes: 45) &&
        (_lastBreathCue == null || DateTime.now().difference(_lastBreathCue!) > const Duration(hours: 2))) {
      _lastBreathCue = DateTime.now();
      play(HapticPattern.swell);
      note('cue breathing break (stress ${stress.value.round()})');
    }
  }

  Future<void> syncNow() async {
    if (!ready || !paired) return;
    await health.sync(ring, features);
    _checkCues();
  }

  void _onEvent(RingEvent e) {
    switch (e) {
      case ConnectionEvent(:final state):
        connection = state;
        if (state == RingConnectionState.ready) {
          _retryCount = 0;
          _retry?.cancel();
          _onReady();
        } else if (state == RingConnectionState.disconnected) {
          _scheduleRetry();
        }
        notifyListeners();
      case BatteryEvent(:final battery):
        this.battery = battery;
        if (battery.level < 15 && !battery.charging && !_lowBatteryCued) {
          _lowBatteryCued = true;
          if (!inQuietHours) play(HapticPattern.shortLong);
        } else if (battery.level >= 20 || battery.charging) {
          _lowBatteryCued = false;
        }
        notifyListeners();
      case VersionsEvent(:final versions):
        this.versions = versions;
        notifyListeners();
      case BluetoothStateEvent(:final poweredOn):
        bluetoothOn = poweredOn;
        if (poweredOn) reconnect();
        notifyListeners();
      case TouchEvent(gesture: TouchGesture.tap):
        final now = DateTime.now();
        if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 700)) {
          _lastTap = null;
          _doubleTaps.add(null);
        } else {
          _lastTap = now;
        }
      case DataUpdatedEvent(kind: 'steps', :final steps?):
        health.updateTodaySteps(steps, e.distanceMeters ?? 0, e.kcal ?? 0);
        _checkCues();
      case DataUpdatedEvent():
        // Batch bursts of "new data" reports into one refresh.
        _resync?.cancel();
        _resync = Timer(const Duration(seconds: 20), syncNow);
      default:
        break;
    }
  }

  /// Runs once the ring accepts commands: clock, profile, goals, settings, data.
  Future<void> _onReady() async {
    await _step('sync time', () async => features = await ring.syncTime());
    note('features ${features.raw}');
    await _step(
        'user profile',
        () => ring.setUserProfile(
              male: profile.sex == Sex.male,
              age: profile.age,
              heightCm: profile.heightCm,
              weightKg: profile.weightKg,
              metric: prefs.metric,
            ));
    await _step('step goal', () => ring.setGoals(steps: prefs.stepGoal));
    if (features.touch) await _step('touch events', () => ring.setTouchEvents(true));
    await _step('battery', () async => battery = await ring.getBattery());
    await _step('versions', () async {
      final v = await ring.getVersions();
      if (v.firmware.isNotEmpty || v.hardware.isNotEmpty) versions = v;
    });
    notifyListeners();
    // During pairing the band is not confirmed yet; settings and sync follow
    // once the user says "Yes, pair it".
    if (!paired) return;
    await applyRingSettings();
    await syncNow();
  }
}
