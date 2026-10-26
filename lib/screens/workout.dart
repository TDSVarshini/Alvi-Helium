import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/models.dart';
import '../format.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/workout_session.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import 'activity.dart';

class LiveWorkoutScreen extends StatefulWidget {
  const LiveWorkoutScreen({super.key, required this.kind, this.startedByTap = false});
  final WorkoutKind kind;
  final bool startedByTap;

  /// True while a workout is on screen, so a double-tap ends it instead of
  /// starting another.
  static bool active = false;

  @override
  State<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends State<LiveWorkoutScreen> {
  late final WorkoutSession session;
  StreamSubscription<void>? _taps;

  @override
  void initState() {
    super.initState();
    LiveWorkoutScreen.active = true;
    final app = context.read<AppState>();
    session = WorkoutSession(app, widget.kind, startedByTap: widget.startedByTap)..start();
    _taps = app.doubleTaps.listen((_) => _finish(byTap: true));
  }

  @override
  void dispose() {
    LiveWorkoutScreen.active = false;
    _taps?.cancel();
    session.dispose();
    super.dispose();
  }

  Future<void> _finish({bool byTap = false}) async {
    final w = await session.finish(byTap: byTap);
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WorkoutSummaryScreen(w)));
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: He.bgEnd,
          title: Text(c.t('End workout?', 'Terminer l’entraînement?'), style: He.sans(20, weight: FontWeight.w600)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('Keep going', 'Continuer'), style: He.sans(16))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(c.t('End and save', 'Terminer'), style: He.sans(16, weight: FontWeight.w700))),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop && await _confirmDiscard()) _finish();
        },
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final s = session;
            final pace = s.pace;
            return Scaffold(
              body: Backdrop(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: He.gutter),
                  child: Column(children: [
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(child: Text(_title(context), style: He.eyebrow(size: 14, color: He.ink))),
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: s.paused ? He.ink4 : He.heart, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(s.paused ? context.t('PAUSED', 'EN PAUSE') : context.t('RECORDING', 'ENREGISTREMENT'), style: He.eyebrow(size: 13)),
                    ]),
                    const SizedBox(height: 24),
                    FittedBox(child: Text(mmss(s.elapsed), style: He.display(130))),
                    const SizedBox(height: 8),
                    Text(
                      s.startedByTap
                          ? context.t('ELAPSED · STARTED BY DOUBLE TAP', 'ÉCOULÉ · DÉMARRÉ PAR DOUBLE TOUCHE')
                          : context.t('ELAPSED', 'ÉCOULÉ'),
                      style: He.eyebrow(),
                    ),
                    const SizedBox(height: 30),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Text(
                          s.zone == 0
                              ? context.t('HEART', 'CŒUR')
                              : '${context.t('HEART', 'CŒUR')} · ZONE ${s.zone}${s.zone == WorkoutSession.targetZone ? context.t(' · TARGET', ' · CIBLE') : ''}',
                          style: He.eyebrow(color: He.ink, size: 13),
                        ),
                      ),
                      Text(s.heartRate > 0 ? '${s.heartRate}' : '—', style: He.sans(54, weight: FontWeight.w300)),
                      const SizedBox(width: 6),
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('BPM', style: He.eyebrow())),
                    ]),
                    const SizedBox(height: 10),
                    ZoneSegments(s.zone),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(context.t('One pulse when you enter your target zone.', 'Une pulsation en entrant dans votre zone cible.'),
                          style: He.sans(16, color: He.ink2)),
                    ),
                    const SizedBox(height: 18),
                    StatGrid(columns: 2, [
                      StatCell(context.t('Distance', 'Distance'), (s.distanceM / 1000).toStringAsFixed(2), unit: 'KM', size: 46),
                      StatCell(context.t('Pace', 'Allure'), pace == null ? '—' : mmss(pace), unit: '/KM', size: 46),
                      StatCell(context.t('Energy', 'Énergie'), '${s.kcal.round()}', unit: 'KCAL', size: 46),
                      StatCell(context.t('Cadence', 'Cadence'), s.cadence == 0 ? '—' : '${s.cadence}', unit: 'SPM', size: 46),
                    ]),
                    const Spacer(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _RoundButton(
                        size: 92,
                        icon: Icons.flag_outlined,
                        label: context.t('Lap', 'Tour'),
                        onTap: () => toast(context, context.t('Lap marked at ${mmss(s.elapsed)}', 'Tour marqué à ${mmss(s.elapsed)}')),
                      ),
                      _RoundButton(
                        size: 140,
                        filled: true,
                        icon: s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        label: s.paused ? context.t('Resume', 'Reprendre') : context.t('Pause', 'Pause'),
                        onTap: s.togglePause,
                      ),
                      _RoundButton(size: 92, icon: Icons.stop_outlined, label: context.t('End', 'Terminer'), onTap: () => _finish()),
                    ]),
                    const SizedBox(height: 18),
                    Text(
                      widget.kind.usesGps
                          ? context.t('Double-tap the core to end. Distance uses your phone\'s GPS.', 'Touchez deux fois le cœur pour terminer. La distance utilise le GPS du téléphone.')
                          : context.t('Double-tap the core to end.', 'Touchez deux fois le cœur pour terminer.'),
                      textAlign: TextAlign.center,
                      style: He.sans(15.5, color: He.ink2),
                    ),
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  String _title(BuildContext c) => switch (widget.kind) {
        WorkoutKind.run => c.t('OUTDOOR RUN', 'COURSE EXTÉRIEURE'),
        WorkoutKind.walk => c.t('WALK', 'MARCHE'),
        WorkoutKind.ride => c.t('RIDE', 'VÉLO'),
        WorkoutKind.poolSwim => c.t('POOL SWIM', 'NATATION'),
        WorkoutKind.strength => c.t('STRENGTH', 'MUSCULATION'),
      };
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.size, required this.icon, required this.label, required this.onTap, this.filled = false});
  final double size;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? He.ink : Colors.transparent,
              border: filled ? null : Border.all(color: He.ink4, width: 1.2),
            ),
            child: Icon(icon, color: filled ? Colors.white : He.ink, size: filled ? 40 : 26),
          ),
        ),
      );
}

class WorkoutSummaryScreen extends StatelessWidget {
  const WorkoutSummaryScreen(this.w, {super.key});
  final RecordedWorkout w;

  @override
  Widget build(BuildContext context) {
    final swim = w.kind == WorkoutKind.poolSwim;
    final title = '${workoutName(context, w.kind).toUpperCase()} · ${shortDate(context, w.start)}';
    final pace = w.pacePerKm;
    final hasDistance = w.distanceM >= 50;
    final rest = w.activeDuration == null ? null : w.duration - w.activeDuration!;
    return DetailPage(
      title: title,
      trailing: IconButton(
        tooltip: context.t('Share', 'Partager'),
        icon: const Icon(Icons.ios_share_rounded, color: He.ink),
        onPressed: () {
          final lines = [
            '${workoutName(context, w.kind)} · ${shortDate(context, w.start)}',
            if (hasDistance) '${(w.distanceM / 1000).toStringAsFixed(2)} km',
            '${context.t('Time', 'Temps')} ${mmss(w.duration)}',
            if (pace != null) '${context.t('Pace', 'Allure')} ${mmss(pace)} /km',
            if (w.kcal > 0) '${w.kcal.round()} kcal',
            if (w.avgHr > 0) '${context.t('Avg HR', 'FC moy.')} ${w.avgHr} · ${context.t('Max', 'Max')} ${w.maxHr}',
            '— ALVI Helium',
          ];
          SharePlus.instance.share(ShareParams(text: lines.join('\n')));
        },
      ),
      footer: PillButton(context.t('Done', 'Terminé'), onTap: () => Navigator.pop(context)),
      children: [
        HeroValue(hasDistance ? [(w.distanceM / 1000).toStringAsFixed(2), 'km'] : [mmss(w.duration)], size: 130),
        const SizedBox(height: 16),
        Text(_story(context), style: He.body(24, He.ink)),
        const SizedBox(height: 22),
        if (swim)
          StatGrid([
            StatCell(context.t('Active', 'Actif'), mmss(w.activeDuration ?? w.duration), size: 36),
            StatCell(context.t('Rest', 'Repos'), rest == null ? '—' : mmss(rest), size: 36),
            StatCell(context.t('Energy', 'Énergie'), '${w.kcal.round()}', unit: 'KCAL', size: 36),
          ])
        else
          StatGrid([
            StatCell(context.t('Time', 'Temps'), mmss(w.duration), size: 36),
            StatCell(context.t('Pace', 'Allure'), pace == null ? '—' : mmss(pace), unit: '/KM', size: 36),
            StatCell(context.t('Energy', 'Énergie'), '${w.kcal.round()}', unit: 'KCAL', size: 36),
            StatCell(context.t('Avg HR', 'FC moy.'), w.avgHr > 0 ? '${w.avgHr}' : '—', size: 36),
            StatCell(context.t('Max HR', 'FC max'), w.maxHr > 0 ? '${w.maxHr}' : '—', size: 36),
            StatCell(context.t('Effort', 'Effort'), w.effort > 0 ? w.effort.toStringAsFixed(1) : '—', size: 36),
          ]),
        if (w.zoneMinutes.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(context.t('TIME IN ZONES', 'TEMPS PAR ZONE'), style: He.eyebrow()),
          ZoneBars(w.zoneMinutes),
        ],
        if (swim) ...[
          const SizedBox(height: 22),
          Text(context.t('HOW IT WAS RECORDED', 'COMMENT C’EST ENREGISTRÉ'), style: He.eyebrow()),
          const SizedBox(height: 8),
          _cueRow(context, null, w.startedByTap ? context.t('Started with a double tap', 'Démarré par double touche') : context.t('Started in the app', 'Démarré dans l’app'), '00:00'),
          _cueRow(context, null, w.endedByTap ? context.t('Ended with a double tap', 'Terminé par double touche') : context.t('Ended in the app', 'Terminé dans l’app'), mmss(w.duration)),
          const SizedBox(height: 16),
          const Hairline(),
          RowTile(
            label: context.t('Lengths and pace: coming soon', 'Longueurs et allure : bientôt'),
            sub: context.t('Lap counting arrives in a later update. Heart rate isn\'t recorded in the water.',
                'Le comptage arrive dans une mise à jour. La fréquence cardiaque n’est pas mesurée dans l’eau.'),
          ),
        ] else if (w.cues.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(context.t('WHAT YOUR BAND TOLD YOU', 'CE QUE VOTRE BRACELET VOUS A DIT'), style: He.eyebrow()),
          const SizedBox(height: 8),
          for (final c in w.cues) _cueRow(context, c, _cueLabel(context, c.label), mmss(c.at)),
        ],
        if (swim)
          Disclaimer(context.t('Water resistance is a design target. ALVI Helium is in development.',
              'La résistance à l’eau est un objectif de conception. ALVI Helium est en développement.')),
      ],
    );
  }

  Widget _cueRow(BuildContext context, WorkoutCue? c, String label, String at) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 96, child: Align(alignment: Alignment.centerLeft, child: HapticGlyph(c?.pattern))),
          Expanded(child: Text(label, style: He.sans(19))),
          Text(at, style: He.mono(15, weight: FontWeight.w700)),
        ]),
      );

  String _cueLabel(BuildContext c, String label) => c.isFrench
      ? label.replaceFirst('In your zone', 'Dans votre zone').replaceFirst('Goal reached', 'Objectif atteint')
      : label;

  String _story(BuildContext c) {
    if (w.kind == WorkoutKind.poolSwim) return c.t('A steady half hour in the water.', 'Une demi-heure régulière dans l’eau.');
    if (w.zoneMinutes.isNotEmpty && (w.zoneMinutes[3] ?? 0) >= w.duration.inMinutes * 0.4) {
      return c.t('Strong and even. Most of it in your target zone.', 'Solide et régulier. Surtout dans votre zone cible.');
    }
    if (w.duration.inMinutes < 15) return c.t('Short and sharp. Every session counts.', 'Court et efficace. Chaque séance compte.');
    return c.t('Done and logged. Recovery starts now.', 'Fait et enregistré. La récupération commence.');
  }
}
