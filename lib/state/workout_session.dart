import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../domain/haptics.dart';
import '../domain/models.dart';
import 'app_state.dart';
import 'permissions.dart';

/// A workout being recorded: ring heart rate + phone GPS + haptic cues.
class WorkoutSession extends ChangeNotifier {
  WorkoutSession(this.app, this.kind, {this.startedByTap = false, this.goalKm = 5});

  final AppState app;
  final WorkoutKind kind;
  final bool startedByTap;
  final double goalKm;
  static const targetZone = 3;

  final _clock = Stopwatch();
  final DateTime startedAt = DateTime.now();
  Timer? _ticker;
  StreamSubscription<int>? _hrSub;
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<RingEvent>? _ringSub;
  Position? _lastFix;

  int heartRate = 0;
  final List<int> _hrSamples = [];
  double distanceM = 0;
  int _ringSteps = 0;
  double _ringKcal = 0;
  final Map<int, int> _zoneSeconds = {};
  final List<WorkoutCue> cues = [];
  int? _zone;
  bool _goalCued = false;
  bool get paused => !_clock.isRunning;

  Duration get elapsed => _clock.elapsed;

  int get zone {
    if (heartRate <= 0) return 0;
    final f = heartRate / app.profile.maxHr;
    return f < 0.6 ? 1 : f < 0.7 ? 2 : f < 0.8 ? 3 : f < 0.9 ? 4 : 5;
  }

  Duration? get pace => distanceM < 50
      ? null
      : Duration(seconds: (elapsed.inSeconds / (distanceM / 1000)).round());

  double get kcal {
    if (_ringKcal > 0) return _ringKcal;
    final km = distanceM / 1000;
    return kind.usesGps ? app.profile.weightKg * km * 1.036 : elapsed.inMinutes * 8.0;
  }

  int get cadence => elapsed.inMinutes == 0 ? 0 : (_ringSteps / (elapsed.inSeconds / 60)).round();

  Future<void> start() async {
    _clock.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (app.ready) {
      try {
        await app.ring.workout(WorkoutAction.start, sportType: kind.ringCode);
      } catch (e) {
        debugPrint('workout start on ring: $e');
      }
      try {
        await app.ring.startRealtimeHeartRate();
      } catch (_) {}
      _hrSub = app.ring.realtimeHeartRate.listen((bpm) {
        heartRate = bpm;
        if (!paused) _hrSamples.add(bpm);
      });
      _ringSub = app.ring.events.listen((e) {
        if (e is WorkoutEvent) {
          if (e.data.heartRate > 0) heartRate = e.data.heartRate;
          _ringSteps = e.data.steps;
          _ringKcal = e.data.kcal;
        }
      });
    }
    if (kind.usesGps && await ensureLocationPermission()) {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
      ).listen(_onFix, onError: (Object e) => debugPrint('gps: $e'));
    }
    notifyListeners();
  }

  void _onFix(Position p) {
    if (!paused && _lastFix != null && p.accuracy < 30) {
      distanceM += Geolocator.distanceBetween(_lastFix!.latitude, _lastFix!.longitude, p.latitude, p.longitude);
    }
    _lastFix = p;
  }

  void _tick() {
    if (paused) return;
    final z = zone;
    if (z > 0) _zoneSeconds[z] = (_zoneSeconds[z] ?? 0) + 1;
    if (z == targetZone && (_zone ?? 0) < targetZone && app.prefs.cues[HapticCue.zone]!) {
      _cue(HapticPattern.onePulse, 'In your zone');
    }
    _zone = z;
    if (!_goalCued && distanceM >= goalKm * 1000) {
      _goalCued = true;
      if (app.prefs.cues[HapticCue.goal]!) _cue(HapticPattern.twoPulses, 'Goal reached · ${goalKm.toStringAsFixed(0)} km');
    }
    notifyListeners();
  }

  void _cue(HapticPattern p, String label) {
    cues.add(WorkoutCue(elapsed, p, label));
    app.play(p);
  }

  Future<void> togglePause() async {
    if (paused) {
      _clock.start();
      _lastFix = null;
    } else {
      _clock.stop();
    }
    if (app.ready) {
      try {
        await app.ring.workout(paused ? WorkoutAction.pause : WorkoutAction.resume, sportType: kind.ringCode);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<RecordedWorkout> finish({bool byTap = false}) async {
    _clock.stop();
    _ticker?.cancel();
    await _hrSub?.cancel();
    await _gpsSub?.cancel();
    await _ringSub?.cancel();
    if (app.ready) {
      try {
        await app.ring.workout(WorkoutAction.stop, sportType: kind.ringCode);
        await app.ring.stopRealtimeHeartRate();
      } catch (_) {}
      app.play(HapticPattern.tick);
    }
    final hr = _hrSamples.where((v) => v > 0).toList();
    final w = RecordedWorkout(
      kind: kind,
      start: startedAt,
      duration: elapsed,
      distanceM: distanceM,
      kcal: kcal,
      avgHr: hr.isEmpty ? 0 : (hr.reduce((a, b) => a + b) / hr.length).round(),
      maxHr: hr.isEmpty ? 0 : hr.reduce((a, b) => a > b ? a : b),
      zoneMinutes: {for (final e in _zoneSeconds.entries) if (e.value >= 30) e.key: (e.value / 60).round()},
      cues: cues,
      startedByTap: startedByTap,
      endedByTap: byTap,
    );
    await app.health.addWorkout(w);
    return w;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _hrSub?.cancel();
    _gpsSub?.cancel();
    _ringSub?.cancel();
    super.dispose();
  }
}
