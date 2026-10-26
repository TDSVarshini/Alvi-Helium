import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../domain/haptics.dart';
import '../format.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Install a firmware .bin from the phone's files onto the band.
class FirmwareScreen extends StatefulWidget {
  const FirmwareScreen({super.key});
  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  StreamSubscription<RingEvent>? _sub;
  int? _percent;
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _pick(AppState app) async {
    final level = app.battery?.level ?? 0;
    if (level < 30) {
      toast(context, context.t('Charge the band above 30% first.', 'Chargez le bracelet à plus de 30 %.'));
      return;
    }
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['bin']);
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    // Copy into app storage: pickers may hand back content:// URIs.
    final local = File('${Directory.systemTemp.path}/helium_fw_${DateTime.now().millisecondsSinceEpoch}.bin');
    await local.writeAsBytes(await file.readAsBytes());
    setState(() {
      _busy = true;
      _percent = 0;
      _status = file.name;
    });
    _sub?.cancel();
    _sub = app.ring.events.listen((e) {
      if (e is! OtaProgressEvent || !mounted) return;
      setState(() {
        _percent = e.percent;
        if (e.done) {
          _busy = false;
          _status = e.error == null
              ? context.t('Updated. The band restarts and reconnects.', 'Mis à jour. Le bracelet redémarre et se reconnecte.')
              : '${context.t('Update failed', 'Échec de la mise à jour')}: ${e.error}';
        }
      });
    });
    try {
      await app.ring.startOta(local.path);
      app.note('ota start ${file.name} (${await local.length()} bytes)');
    } catch (e) {
      setState(() {
        _busy = false;
        _status = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final v = app.versions;
    return PopScope(
      canPop: !_busy,
      child: DetailPage(
        title: context.t('Firmware', 'Micrologiciel'),
        footer: PillButton(
          _busy ? context.t('Updating…', 'Mise à jour…') : context.t('Choose firmware file', 'Choisir un fichier'),
          onTap: app.ready && !_busy ? () => _pick(app) : null,
        ),
        children: [
          const Hairline(),
          RowTile(label: context.t('Firmware', 'Micrologiciel'), value: v?.firmware.isNotEmpty == true ? v!.firmware : '—', mono: true),
          RowTile(label: context.t('Hardware', 'Matériel'), value: v?.hardware.isNotEmpty == true ? v!.hardware : '—', mono: true),
          RowTile(label: context.t('Battery', 'Batterie'), value: app.battery == null ? '—' : '${app.battery!.level}%', mono: true),
          const SizedBox(height: 24),
          if (_percent != null) ...[
            Text('$_percent%', style: He.display(80)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _percent! / 100, minHeight: 3, color: He.ink, backgroundColor: He.track),
            const SizedBox(height: 12),
          ],
          if (_status != null) Text(_status!, style: He.body()),
          Disclaimer(context.t(
              'Use only firmware files supplied by ALVI for your band\'s hardware version. Keep the phone next to the band and the app open until it finishes.',
              'N’utilisez que les fichiers fournis par ALVI pour votre version matérielle. Gardez le téléphone près du bracelet et l’app ouverte.')),
        ],
      ),
    );
  }
}

/// Tester view: live connection facts, one-tap commands, raw history and
/// the event log. Everything shown is what the native SDK returned.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _out = <String>[];
  StreamSubscription<int>? _hr;
  bool _realtime = false;
  int _day = 0;

  @override
  void dispose() {
    _hr?.cancel();
    if (_realtime) context.read<AppState>().ring.stopRealtimeHeartRate().catchError((_) {});
    super.dispose();
  }

  void _print(String s) => setState(() => _out.insert(0, '${clock(DateTime.now())}:${two(DateTime.now().second)}  $s'));

  Future<void> _run(String name, Future<Object?> Function() f) async {
    _print('→ $name');
    final sw = Stopwatch()..start();
    try {
      final r = await f();
      _print('✓ $name (${sw.elapsedMilliseconds} ms)${r == null ? '' : '\n$r'}');
    } catch (e) {
      _print('✗ $name (${sw.elapsedMilliseconds} ms) $e');
    }
  }

  String _series(List<Sample> s, {int digits = 0}) {
    if (s.isEmpty) return 'no samples';
    final v = s.map((x) => x.value);
    return '${s.length} samples · ${clock(s.first.time)}–${clock(s.last.time)} · '
        'min ${v.reduce(math.min).toStringAsFixed(digits)} max ${v.reduce(math.max).toStringAsFixed(digits)} '
        'last ${s.last.value.toStringAsFixed(digits)}';
  }

  Future<void> _history(QRing r) async {
    final d = _day;
    await _run('sleep day $d', () async {
      final n = await r.getSleep(d);
      if (n == null) return 'none';
      return '${n.start} → ${n.end}\ntotal ${n.totalMinutes} min · deep ${n.deepMinutes} · light ${n.lightMinutes} · '
          'rem ${n.remMinutes} · awake ${n.awakeMinutes} · ring score ${n.score} · ${n.segments.length} segments';
    });
    await _run('heart rate day $d', () async => _series(await r.getHeartRate(d)));
    await _run('HRV day $d (raw, ms?)', () async => _series(await r.getHrv(d)));
    await _run('stress day $d (raw)', () async => _series(await r.getStress(d)));
    await _run('SpO2 day $d', () async => _series(await r.getSpO2(d)));
    await _run('temperature day $d (°C?)', () async => _series(await r.getTemperature(d), digits: 2));
    await _run('blood pressure day $d', () async {
      final l = await r.getBloodPressure(d);
      return l.isEmpty ? 'none' : l.map((b) => '${clock(b.time)} ${b.systolic}/${b.diastolic}').join(', ');
    });
    await _run('activity day $d (kcal?)', () async {
      final a = await r.getActivitySummary(d);
      return 'steps ${a.steps} · distance ${a.distanceMeters} m · kcal ${a.kcal.toStringAsFixed(1)} · active ${a.activeMinutes} min';
    });
    await _run('workouts day $d', () async {
      final w = await r.getWorkouts(d);
      return w.isEmpty
          ? 'none'
          : w.map((x) => 'type ${x.type} ${x.start} ${x.durationSeconds}s ${x.distanceMeters}m ${x.kcal}kcal hr ${x.avgHr}/${x.maxHr}').join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = app.ring;
    Widget btn(String label, VoidCallback? onTap) => OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: He.ink,
            side: const BorderSide(color: He.ink4),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          child: Text(label, style: He.sans(14.5)),
        );
    final on = app.ready;
    final facts = [
      'state      ${app.connection.name}${app.bluetoothOn ? '' : ' (phone Bluetooth off)'}',
      'device     ${app.deviceName ?? '—'}  ${app.deviceId ?? 'not paired'}',
      'mac        ${app.deviceMac ?? '—'}',
      'battery    ${app.battery == null ? '—' : '${app.battery!.level}%${app.battery!.charging ? ' charging' : ''}'}',
      'firmware   ${app.versions?.firmware ?? '—'}   hardware ${app.versions?.hardware ?? '—'}',
      'features   ${app.features.raw.entries.where((e) => e.value).map((e) => e.key).join(', ')}',
      'last sync  ${app.health.lastSync ?? '—'}',
    ];
    return DetailPage(
      title: context.t('Diagnostics', 'Diagnostic'),
      trailing: IconButton(
        tooltip: context.t('Copy log', 'Copier le journal'),
        icon: const Icon(Icons.copy_rounded, color: He.ink),
        onPressed: () {
          final text = [
            ...facts,
            '',
            ..._out,
            '',
            '--- event log ---',
            for (final (t, l) in app.log.reversed) '${t.toIso8601String()}  $l',
          ].join('\n');
          Clipboard.setData(ClipboardData(text: text));
          toast(context, context.t('Copied to clipboard', 'Copié'));
        },
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: He.panel, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(facts.join('\n'), style: He.mono(12.5, weight: FontWeight.w500)),
        ),
        const SizedBox(height: 16),
        Text('CONNECTION', style: He.eyebrow()),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          btn('Reconnect', app.paired && !on ? app.reconnect : null),
          btn('Sync now', on ? () => _run('full sync', () async {
                await app.syncNow();
                return 'nights stored ${app.health.history.length}';
              }) : null),
          btn('Push settings', on ? () => _run('apply settings', () async {
                await app.applyRingSettings();
                return 'see event log';
              }) : null),
          btn('Battery', on ? () => _run('battery', () async {
                final b = await r.getBattery();
                return '${b.level}% charging=${b.charging}';
              }) : null),
          btn('Versions', on ? () => _run('versions', () async {
                final v = await r.getVersions();
                return 'fw ${v.firmware} hw ${v.hardware}';
              }) : null),
          btn('Features', on ? () => _run('syncTime', () async => (await r.syncTime()).raw.toString()) : null),
        ]),
        const SizedBox(height: 12),
        Text('HAPTICS', style: He.eyebrow()),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          btn('Find band', on ? () => _run('find device', () async => r.findDevice()) : null),
          btn('Vibrate 1×', on ? () => _run('vibrate', () async => r.vibrate()) : null),
          for (final p in [HapticPattern.twoPulses, HapticPattern.rising, HapticPattern.shortLong])
            btn(p.name, on ? () => _run('pattern ${p.name}', () async => app.play(p)) : null),
          btn('Read alarms', on ? () => _run('alarms', () async => (await r.getAlarms()).toString()) : null),
        ]),
        const SizedBox(height: 12),
        Text('MEASURE NOW', style: He.eyebrow()),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final t in MeasurementType.values)
            btn(t.name, on && app.features.appMeasure || on && t == MeasurementType.heartRate
                ? () => _run('measure ${t.name}', () async {
                      final m = await r.measure(t);
                      return m.systolic != null ? '${m.systolic}/${m.diastolic}' : m.value.toString();
                    })
                : null),
          btn(_realtime ? 'Stop live HR' : 'Live HR', on
              ? () async {
                  if (_realtime) {
                    await _hr?.cancel();
                    await r.stopRealtimeHeartRate();
                    _print('live HR stopped');
                  } else {
                    _hr = r.realtimeHeartRate.listen((b) => _print('live HR $b bpm'));
                    await r.startRealtimeHeartRate();
                    _print('live HR started');
                  }
                  setState(() => _realtime = !_realtime);
                }
              : null),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('RAW HISTORY · DAY $_day', style: He.eyebrow())),
          IconButton(onPressed: _day > 0 ? () => setState(() => _day--) : null, icon: const Icon(Icons.remove_rounded)),
          IconButton(onPressed: _day < 6 ? () => setState(() => _day++) : null, icon: const Icon(Icons.add_rounded)),
        ]),
        btn('Read all history for day $_day', on ? () => _history(r) : null),
        const SizedBox(height: 16),
        Text('RESULTS', style: He.eyebrow()),
        const SizedBox(height: 8),
        if (_out.isEmpty) Text('Run a command above.', style: He.sans(14.5, color: He.ink3)),
        for (final line in _out)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText(line, style: He.mono(12, weight: FontWeight.w500)),
          ),
        const SizedBox(height: 16),
        Text('EVENT LOG (${app.log.length})', style: He.eyebrow()),
        const SizedBox(height: 8),
        for (final (t, l) in app.log.reversed.take(80))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${clock(t)}:${two(t.second)}  $l', style: He.mono(11.5, weight: FontWeight.w400, color: He.ink3)),
          ),
      ],
    );
  }
}
