import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../domain/haptics.dart';
import '../domain/models.dart';
import '../format.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/health_store.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../state/backup_io.dart';
import 'device_tools.dart';
import 'onboarding.dart';
import 'shell.dart';

String strengthName(BuildContext c, HapticStrength s) => switch (s) {
      HapticStrength.soft => c.t('Soft', 'Douce'),
      HapticStrength.medium => c.t('Medium', 'Moyenne'),
      HapticStrength.strong => c.t('Strong', 'Forte'),
    };

String wearName(BuildContext c, Prefs p) =>
    '${p.wear == WearSpot.wrist ? c.t('Wrist', 'Poignet') : c.t('Upper arm', 'Haut du bras')} · ${p.size.name.toUpperCase()}';

void _open(BuildContext c, Widget page) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => page));

class YouTab extends StatelessWidget {
  const YouTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final health = context.watch<HealthStore>();
    final worn = health.history.where((n) => n.worn).length;
    var streak = 0;
    for (final n in health.history.reversed) {
      if (!n.worn) break;
      streak++;
    }
    // Weekly readiness: average per 7-day block, last five weeks.
    final weekly = <double>[];
    for (var w = 4; w >= 0; w--) {
      final block = [for (var d = w * 7; d < w * 7 + 7; d++) health.summaryFor(HealthStore.dateOf(d))]
          .whereType<NightSummary>()
          .where((n) => n.readiness > 0);
      if (block.isNotEmpty) weekly.add(block.map((n) => n.readiness).reduce((a, b) => a + b) / block.length);
    }
    return TabPage(children: [
      Text('${context.t('MEMBER SINCE', 'MEMBRE DEPUIS')} ${monthName(context, app.profile.memberSince)}', style: He.eyebrow(size: 14)),
      const SizedBox(height: 4),
      Text(app.profile.name.isEmpty ? context.t('You', 'Vous') : app.profile.name, style: He.display(64)),
      const SizedBox(height: 18),
      StatGrid(columns: 2, [
        StatCell(context.t('Nights worn', 'Nuits portées'), '$worn', size: 64),
        StatCell(context.t('Night streak', 'Série de nuits'), '$streak', size: 64),
      ]),
      const SizedBox(height: 18),
      Text(context.t('WEEKLY READINESS', 'DISPONIBILITÉ HEBDO'), style: He.eyebrow()),
      const SizedBox(height: 8),
      weekly.length < 2
          ? EmptyNote(context.t('Your weekly trend appears after two weeks of wear.', 'Votre tendance apparaît après deux semaines.'))
          : TrendLine(weekly),
      if (weekly.length >= 2)
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var w = weekly.length - 1; w >= 0; w--)
            Text(w == 0 ? context.t('NOW', 'MAINT.') : shortDate(context, HealthStore.dateOf(w * 7)).substring(4),
                style: He.mono(13, color: w == 0 ? He.ink : He.ink2)),
        ]),
      const SizedBox(height: 18),
      const Hairline(),
      RowTile(
        label: context.t('Your Helium', 'Votre Helium'),
        value: !app.paired ? context.t('Not paired', 'Non jumelé') : app.battery == null ? '—' : '${app.battery!.level}%',
        chevron: true,
        height: 84,
        onTap: () => _open(context, app.paired ? const DeviceScreen() : const WakeStep()),
      ),
      RowTile(
        label: context.t('Haptics', 'Haptique'),
        value: strengthName(context, app.prefs.strength),
        chevron: true,
        height: 84,
        onTap: () => _open(context, const HapticsScreen()),
      ),
      RowTile(
        label: context.t('Profile and baselines', 'Profil et références'),
        value: '${app.profile.heightCm} cm · ${app.profile.weightKg} kg',
        chevron: true,
        height: 84,
        onTap: () => _open(context, const AboutYouStep(editing: true)),
      ),
      RowTile(
        label: context.t('Privacy and data', 'Confidentialité et données'),
        chevron: true,
        height: 84,
        onTap: () => _open(context, const PrivacyScreen()),
      ),
      RowTile(
        label: 'Language · Langue',
        value: app.prefs.french ? 'Français' : 'English',
        chevron: true,
        height: 84,
        onTap: () => app.setFrench(!app.prefs.french),
      ),
      RowTile(
        label: context.t('Diagnostics', 'Diagnostic'),
        chevron: true,
        height: 84,
        onTap: () => _open(context, const DiagnosticsScreen()),
      ),
    ]);
  }
}

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});
  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  bool _finding = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final level = app.battery?.level;
    final state = switch (app.connection) {
      RingConnectionState.ready => context.t('CONNECTED', 'CONNECTÉ'),
      RingConnectionState.connecting || RingConnectionState.connected => context.t('CONNECTING', 'CONNEXION'),
      RingConnectionState.disconnected => context.t('OFFLINE', 'HORS LIGNE'),
    };
    // Design target: ~7 days on a full charge.
    final days = level == null ? null : (level / 100 * 7.3).floor();
    return DetailPage(title: context.t('Your Helium', 'Votre Helium'), children: [
      const CoreGlyph(),
      const SizedBox(height: 10),
      Center(child: Eyebrow('$state · ${app.prefs.wear == WearSpot.wrist ? context.t('WRIST', 'POIGNET') : context.t('UPPER ARM', 'HAUT DU BRAS')}', dot: app.ready ? He.ink : He.ink4, color: He.ink2)),
      const SizedBox(height: 24),
      Text(context.t('BATTERY', 'BATTERIE'), style: He.eyebrow()),
      HeroValue([level?.toString() ?? '—', '%'], size: 110),
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          app.battery?.charging == true
              ? context.t('CHARGING', 'EN CHARGE')
              : days == null
                  ? ''
                  : context.t('ABOUT $days DAYS LEFT*', 'ENVIRON $days JOURS*'),
          style: He.mono(15, weight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 10),
      LinearProgressIndicator(value: (level ?? 0) / 100, minHeight: 3, color: He.ink, backgroundColor: He.track),
      const SizedBox(height: 18),
      const Hairline(),
      RowTile(label: context.t('Haptics', 'Haptique'), value: strengthName(context, app.prefs.strength), chevron: true, height: 84, onTap: () => _open(context, const HapticsScreen())),
      RowTile(label: context.t('Wear', 'Port'), value: wearName(context, app.prefs), chevron: true, height: 84, onTap: () => _open(context, const WearStep(editing: true))),
      RowTile(
        label: context.t('Find my band', 'Trouver mon bracelet'),
        sub: context.t('It pulses for 10 seconds', 'Il pulse pendant 10 secondes'),
        valueWidget: _finding
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: He.ink))
            : const HapticGlyph(HapticPattern.rising),
        onTap: !app.ready
            ? null
            : () async {
                setState(() => _finding = true);
                try {
                  await app.ring.findDevice();
                } catch (_) {}
                await Future<void>.delayed(const Duration(seconds: 10));
                if (mounted) setState(() => _finding = false);
              },
      ),
      RowTile(
        label: context.t('Share heart rate', 'Partager la fréquence cardiaque'),
        sub: context.t('Broadcast to gym equipment', 'Diffuser aux appareils de gym'),
        valueWidget: HeToggle(
          value: app.prefs.shareHeartRate,
          onChanged: (v) {
            // The ring firmware has no standard heart-rate broadcast yet.
            toast(context, context.t('Heart-rate broadcast arrives with a firmware update.', 'La diffusion arrivera avec une mise à jour du micrologiciel.'));
          },
        ),
      ),
      RowTile(
        label: context.t('Firmware', 'Micrologiciel'),
        value: app.versions?.firmware.isNotEmpty == true ? app.versions!.firmware : '—',
        mono: true,
        chevron: true,
        height: 84,
        onTap: () => _open(context, const FirmwareScreen()),
      ),
      RowTile(
        label: context.t('Diagnostics', 'Diagnostic'),
        sub: context.t('Raw readings, commands and the event log', 'Données brutes, commandes et journal'),
        chevron: true,
        onTap: () => _open(context, const DiagnosticsScreen()),
      ),
      Disclaimer(context.t('* Design target. ALVI Helium is in development.', '* Objectif de conception. ALVI Helium est en développement.')),
      const SizedBox(height: 18),
      PillButton(context.t('Unpair', 'Dissocier'), outlined: true, height: 46, onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: He.bgEnd,
            title: Text(c.t('Unpair this band?', 'Dissocier ce bracelet?'), style: He.sans(20, weight: FontWeight.w600)),
            content: Text(c.t('Your history stays on this phone. You can pair again any time.', 'Votre historique reste sur ce téléphone.'), style: He.body(16)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('Cancel', 'Annuler'), style: He.sans(16))),
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(c.t('Unpair', 'Dissocier'), style: He.sans(16, weight: FontWeight.w700, color: He.heart))),
            ],
          ),
        );
        if (ok == true) {
          await app.unpair();
          if (context.mounted) Navigator.pop(context);
        }
      }),
    ]);
  }
}

class HapticsScreen extends StatelessWidget {
  const HapticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.prefs;
    final rows = [
      (HapticPattern.onePulse, HapticCue.zone, context.t('Zone cues', 'Signaux de zone'), context.t('When you enter your target zone', 'En entrant dans votre zone cible')),
      (HapticPattern.twoPulses, HapticCue.goal, context.t('Goal reached', 'Objectif atteint'), context.t('Steps and workout goals', 'Pas et objectifs d’entraînement')),
      (HapticPattern.longPulse, HapticCue.move, context.t('Move nudges', 'Rappels de bouger'), context.t('After 60 min sitting', 'Après 60 min assis')),
      (HapticPattern.rising, HapticCue.alarm, context.t('Silent alarm', 'Alarme silencieuse'), context.t('Inside your wake window', 'Dans votre fenêtre de réveil')),
      (HapticPattern.swell, HapticCue.breathe, context.t('Breathing breaks', 'Pauses respiration'), context.t('When stress looks high', 'Quand le stress semble élevé')),
    ];
    return DetailPage(
      title: context.t('Haptics', 'Haptique'),
      footer: PillButton(context.t('Feel them again', 'Les ressentir'), onTap: app.ready
          ? () async {
              for (final r in rows) {
                if (p.cues[r.$2]!) {
                  await app.play(r.$1);
                  await Future<void>.delayed(const Duration(milliseconds: 900));
                }
              }
            }
          : null),
      children: [
        Text(context.t('Tune how Helium speaks to you.', 'Réglez la façon dont Helium vous parle.'), style: He.headline()),
        const SizedBox(height: 22),
        Text(context.t('STRENGTH', 'INTENSITÉ'), style: He.eyebrow()),
        const SizedBox(height: 12),
        Segmented<HapticStrength>(
          options: {for (final s in HapticStrength.values) s: strengthName(context, s)},
          value: p.strength,
          onChanged: (s) {
            p.strength = s;
            app.save();
            app.play(HapticPattern.onePulse);
          },
        ),
        const SizedBox(height: 20),
        const Hairline(),
        for (final (pattern, cue, title, sub) in rows)
          _CueRow(pattern: pattern, title: title, sub: sub, trailing: HeToggle(value: p.cues[cue]!, onChanged: (v) {
            p.cues[cue] = v;
            app.save();
            if (cue == HapticCue.move) app.applyMoveNudges();
            if (cue == HapticCue.alarm) app.applyAlarm();
          })),
        _CueRow(
          pattern: HapticPattern.shortLong,
          title: context.t('Battery low', 'Batterie faible'),
          sub: context.t('Below 15%', 'Sous 15 %'),
          trailing: Text(context.t('Always on', 'Toujours actif'), style: He.sans(15.5, color: He.ink2)),
        ),
        const SizedBox(height: 20),
        RowTile(
          label: context.t('Quiet hours', 'Heures calmes'),
          value: '${clockMin(p.quietStart)} — ${clockMin(p.quietEnd)}',
          mono: true,
          height: 84,
          onTap: () async {
            final start = await showTimePicker(context: context, initialTime: TimeOfDay(hour: p.quietStart ~/ 60, minute: p.quietStart % 60));
            if (start == null || !context.mounted) return;
            final end = await showTimePicker(context: context, initialTime: TimeOfDay(hour: p.quietEnd ~/ 60, minute: p.quietEnd % 60));
            if (end == null) return;
            p.quietStart = start.hour * 60 + start.minute;
            p.quietEnd = end.hour * 60 + end.minute;
            app.save();
            app.applyQuietHours();
          },
        ),
      ],
    );
  }
}

class _CueRow extends StatelessWidget {
  const _CueRow({required this.pattern, required this.title, required this.sub, required this.trailing});
  final HapticPattern pattern;
  final String title, sub;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.read<AppState>().play(pattern),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: He.hairline))),
          child: Row(children: [
            SizedBox(width: 96, child: Align(alignment: Alignment.centerLeft, child: HapticGlyph(pattern))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: He.sans(19)),
                Text(sub, style: He.sans(15, color: He.ink3)),
              ]),
            ),
            trailing,
          ]),
        ),
      );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nights = app.health.history.where((n) => n.worn).length;
    return DetailPage(title: context.t('Privacy and data', 'Confidentialité'), children: [
      Text(context.t('Your body.\nYour data.', 'Votre corps.\nVos données.'), style: He.headline()),
      const SizedBox(height: 18),
      const PrivacyChoices(),
      const SizedBox(height: 28),
      Text(context.t('ON THIS PHONE', 'SUR CE TÉLÉPHONE'), style: He.eyebrow()),
      const SizedBox(height: 8),
      const Hairline(),
      RowTile(
        label: context.t('Export a backup', 'Exporter une sauvegarde'),
        sub: context.t('$nights nights, workouts, profile and settings as one file', '$nights nuits, entraînements, profil et réglages en un fichier'),
        chevron: true,
        onTap: app.health.demo ? null : () => shareBackup(app),
      ),
      RowTile(
        label: context.t('Restore a backup', 'Restaurer une sauvegarde'),
        sub: context.t('Replaces what is on this phone', 'Remplace ce qui est sur ce téléphone'),
        chevron: true,
        onTap: () async {
          try {
            if (await pickAndRestoreBackup(app) && context.mounted) {
              toast(context, context.t('Backup restored.', 'Sauvegarde restaurée.'));
            }
          } catch (e) {
            if (context.mounted) toast(context, context.t('That file isn’t a Helium backup.', 'Ce fichier n’est pas une sauvegarde Helium.'));
          }
        },
      ),
      RowTile(
        label: context.t('Delete all data', 'Supprimer toutes les données'),
        sub: context.t('Unpairs the band and erases everything Helium stored', 'Dissocie le bracelet et efface tout'),
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              backgroundColor: He.bgEnd,
              title: Text(c.t('Delete everything?', 'Tout supprimer?'), style: He.sans(20, weight: FontWeight.w600)),
              content: Text(c.t('This can’t be undone. Export a backup first if you may want it later.',
                  'Action irréversible. Exportez une sauvegarde d’abord si besoin.'), style: He.body(16)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('Cancel', 'Annuler'), style: He.sans(16))),
                TextButton(onPressed: () => Navigator.pop(c, true),
                    child: Text(c.t('Delete', 'Supprimer'), style: He.sans(16, weight: FontWeight.w700, color: He.heart))),
              ],
            ),
          );
          if (ok == true) {
            await app.eraseEverything();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
            }
          }
        },
      ),
      Disclaimer(context.t('Consent under PIPEDA and Québec Law 25. Privacy officer: [CONTACT].',
          'Consentement selon la LPRPDE et la Loi 25 du Québec. Responsable : [CONTACT].')),
    ]);
  }
}
