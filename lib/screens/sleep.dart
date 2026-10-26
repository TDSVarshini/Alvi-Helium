import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../domain/insights.dart';
import '../domain/haptics.dart';
import '../format.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/health_store.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import 'shell.dart';

class SleepTab extends StatelessWidget {
  const SleepTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final health = context.watch<HealthStore>();
    final night = health.today?.sleep;
    final a = app.prefs.alarm;
    final alarmRow = RowTile(
      label: context.t('Silent alarm', 'Alarme silencieuse'),
      value: a.enabled ? '${clockMin(a.earliest)} — ${clockMin(a.latest)}' : context.t('Off', 'Désactivée'),
      mono: a.enabled,
      chevron: true,
      height: 84,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SilentAlarmScreen())),
    );
    if (night == null) {
      return TabPage(children: [
        Text(context.t('LAST NIGHT', 'LA NUIT DERNIÈRE'), style: He.eyebrow(size: 14)),
        EmptyNote(context.t('No sleep recorded yet. Wear Helium to bed and it will be here in the morning.',
            'Aucun sommeil enregistré. Portez Helium au lit et il apparaîtra au matin.')),
        alarmRow,
      ]);
    }
    final (title, body) = _story(context, night, health);
    return TabPage(children: [
      Row(children: [
        Expanded(child: Text(context.t('LAST NIGHT', 'LA NUIT DERNIÈRE'), style: He.eyebrow(size: 14))),
        Text('${clock(night.start)} — ${clock(night.end)}', style: He.mono(15, weight: FontWeight.w700)),
      ]),
      const SizedBox(height: 16),
      HeroValue(['${night.totalMinutes ~/ 60}', 'h', two(night.totalMinutes % 60), 'm'], size: 140),
      const SizedBox(height: 18),
      Text(title, style: He.headline(32)),
      const SizedBox(height: 8),
      Text(body, style: He.body(18)),
      const SizedBox(height: 26),
      Hypnogram(night, labels: [
        context.t('AWAKE', 'ÉVEIL'),
        'REM',
        context.t('LIGHT', 'LÉGER'),
        context.t('DEEP', 'PROFOND'),
      ]),
      const SizedBox(height: 16),
      StatGrid([
        StatCell(context.t('Score', 'Score'), '${Insights.sleepScore(night)}', size: 44),
        StatCell(context.t('Deep', 'Profond'), hm(night.deepMinutes), size: 44),
        StatCell('REM', hm(night.remMinutes), size: 44),
      ]),
      const SizedBox(height: 20),
      alarmRow,
    ]);
  }

  (String, String) _story(BuildContext c, SleepNight n, HealthStore h) {
    final total = n.totalMinutes == 0 ? 1 : n.totalMinutes;
    final deepShare = n.deepMinutes / total;
    final awakeShare = n.awakeMinutes / (total + n.awakeMinutes);
    final title = total < 360
        ? c.t('A short night.', 'Une nuit courte.')
        : awakeShare > 0.1
            ? c.t('Restless, but you slept.', 'Agitée, mais vous avez dormi.')
            : deepShare >= 0.17
                ? c.t('Deep, unbroken rest.', 'Repos profond et continu.')
                : c.t('Solid, steady sleep.', 'Un sommeil solide et régulier.');

    final month = h.history.where((x) => DateTime.now().difference(x.date).inDays < 31 && x.worn).toList();
    final longest = month.every((x) => x.deepMin <= n.deepMinutes);
    final twoAm = DateTime(n.end.year, n.end.month, n.end.day, 2);
    final deepSegs = n.segments.where((s) => s.stage == SleepStage.deep);
    final early = deepSegs.where((s) => s.start.isBefore(twoAm)).fold(0, (a, s) => a + s.duration.inMinutes);
    final mostlyEarly = n.deepMinutes > 0 && early / n.deepMinutes > 0.6;
    final body = longest && month.length > 3
        ? (mostlyEarly
            ? c.t('Your longest deep sleep this month, mostly before 02:00.', 'Votre plus long sommeil profond du mois, surtout avant 2 h.')
            : c.t('Your longest deep sleep this month.', 'Votre plus long sommeil profond du mois.'))
        : total < 360
            ? c.t('Aim for an earlier bedtime tonight; your baseline is closer to ${hm(_avg(month))}.',
                'Visez un coucher plus tôt ce soir; votre moyenne est près de ${hm(_avg(month))}.')
            : c.t('${hm(n.deepMinutes)} of deep sleep and ${hm(n.remMinutes)} of REM.',
                '${hm(n.deepMinutes)} de sommeil profond et ${hm(n.remMinutes)} de paradoxal.');
    return (title, body);
  }

  int _avg(List x) => x.isEmpty ? 480 : (x.fold<int>(0, (a, n) => a + n.sleepMin as int) / x.length).round();
}

class SilentAlarmScreen extends StatefulWidget {
  const SilentAlarmScreen({super.key});
  @override
  State<SilentAlarmScreen> createState() => _SilentAlarmScreenState();
}

class _SilentAlarmScreenState extends State<SilentAlarmScreen> {
  late final app = context.read<AppState>();
  late final a = app.prefs.alarm;
  static const rangeStart = 6 * 60, rangeEnd = 7 * 60 + 30;

  @override
  Widget build(BuildContext context) {
    final days = [
      context.t('M', 'L'), context.t('T', 'M'), context.t('W', 'M'), context.t('T', 'J'),
      context.t('F', 'V'), context.t('S', 'S'), context.t('S', 'D'),
    ];
    return DetailPage(
      title: context.t('Silent alarm', 'Alarme silencieuse'),
      trailing: Padding(padding: const EdgeInsets.only(right: 8), child: HeToggle(value: a.enabled, onChanged: (v) => setState(() => a.enabled = v))),
      footer: PillButton(context.t('Save window', 'Enregistrer'), onTap: () {
        if (a.days.isEmpty) a.enabled = false;
        app.save();
        app.applyAlarm(
          title: context.t('Time to wake', 'C’est l’heure'),
          body: context.t('Your silent alarm window has ended.', 'Votre fenêtre de réveil silencieux est terminée.'),
        );
        Navigator.pop(context);
      }),
      children: [
        Text(context.t('Wake on a light moment.', 'Réveil au bon moment.'), style: He.headline()),
        const SizedBox(height: 12),
        Text(context.t('Rising pulses at your lightest sleep, inside your window. No sound, so no one else wakes.',
            'Des pulsations croissantes à votre sommeil le plus léger, dans votre fenêtre. Aucun son.'), style: He.body()),
        const SizedBox(height: 8),
        Text(
          context.t('Current band firmware wakes you at the end of the window; light-sleep timing arrives with a firmware update.',
              'Le micrologiciel actuel vous réveille à la fin de la fenêtre; le réveil en sommeil léger arrivera avec une mise à jour.'),
          style: He.sans(14.5, color: He.ink3),
        ),
        const SizedBox(height: 26),
        Row(children: [
          Expanded(child: Text(context.t('EARLIEST', 'AU PLUS TÔT'), style: He.eyebrow())),
          Text(context.t('LATEST', 'AU PLUS TARD'), style: He.eyebrow()),
        ]),
        FittedBox(
          child: Row(children: [
            Text(clockMin(a.earliest), style: He.display(84)),
            const SizedBox(width: 30),
            Text(clockMin(a.latest), style: He.display(84, color: He.ink2)),
          ]),
        ),
        const SizedBox(height: 10),
        Opacity(
          opacity: a.enabled ? 1 : 0.4,
          child: RangeSlider(
            values: RangeValues(a.earliest.toDouble(), a.latest.toDouble()),
            min: rangeStart.toDouble(),
            max: rangeEnd.toDouble(),
            divisions: (rangeEnd - rangeStart) ~/ 5,
            activeColor: He.deep,
            inactiveColor: He.track,
            onChanged: (v) => setState(() {
              a.earliest = v.start.round();
              a.latest = v.end.round();
            }),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var m = rangeStart; m <= rangeEnd; m += 30) Text(clockMin(m), style: He.mono(13)),
        ]),
        const SizedBox(height: 26),
        Text(context.t('REPEAT', 'RÉPÉTER'), style: He.eyebrow()),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var d = 1; d <= 7; d++)
            GestureDetector(
              onTap: () => setState(() => a.days.contains(d) ? a.days.remove(d) : a.days.add(d)),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.days.contains(d) ? He.ink : Colors.transparent,
                  border: Border.all(color: a.days.contains(d) ? He.ink : He.ink4),
                ),
                child: Text(days[d - 1], style: He.sans(16, weight: FontWeight.w600, color: a.days.contains(d) ? Colors.white : He.ink2)),
              ),
            ),
        ]),
        const SizedBox(height: 18),
        const Hairline(),
        RowTile(
          label: context.t('Pulse pattern', 'Motif'),
          height: 72,
          onTap: () => app.play(HapticPattern.rising),
          valueWidget: Row(children: [
            const HapticGlyph(HapticPattern.rising),
            const SizedBox(width: 8),
            Text(context.t('Rising pulses', 'Croissantes'), style: He.sans(17, color: He.ink2)),
          ]),
        ),
        RowTile(
          label: context.t('Phone sound backup', 'Son du téléphone en appoint'),
          sub: context.t('If you sleep through the pulses', 'Si les pulsations ne vous réveillent pas'),
          valueWidget: HeToggle(value: a.phoneBackup, onChanged: (v) => setState(() => a.phoneBackup = v)),
        ),
      ],
    );
  }
}
