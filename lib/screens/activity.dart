import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../format.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/health_store.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import 'shell.dart';
import 'workout.dart';

class ActivityTab extends StatelessWidget {
  const ActivityTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final health = context.watch<HealthStore>();
    final a = health.today?.activity;
    final goal = app.prefs.stepGoal;
    final steps = a?.steps ?? 0;
    final f = steps / goal;
    final left = (goal - steps).clamp(0, goal);
    final walkMin = (left / 105).round(); // ~105 steps per minute of brisk walking
    final line = steps == 0
        ? context.t('Your day starts at zero. Every walk counts.', 'La journée commence à zéro. Chaque marche compte.')
        : f >= 1
            ? context.t('Goal closed. Anything more is a bonus.', 'Objectif atteint. Le reste est un bonus.')
            : f >= 0.45 && f <= 0.6
                ? context.t('Halfway there. A $walkMin-minute walk closes it.', 'À mi-chemin. Une marche de $walkMin minutes suffit.')
                : context.t('A $walkMin-minute walk closes it.', 'Une marche de $walkMin minutes suffit.');
    return TabPage(children: [
      Row(children: [
        Expanded(child: Text(context.t('ACTIVITY · TODAY', 'ACTIVITÉ · AUJOURD’HUI'), style: He.eyebrow(size: 14))),
        Text('${context.t('GOAL', 'OBJECTIF')} ${thousands(context, goal)}', style: He.mono(15, weight: FontWeight.w700)),
      ]),
      const SizedBox(height: 14),
      FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(thousands(context, steps), style: He.display(150))),
      const SizedBox(height: 6),
      TickProgress(f),
      const SizedBox(height: 16),
      Text(line, style: He.body(24, He.ink)),
      const SizedBox(height: 22),
      StatGrid([
        StatCell(context.t('Active', 'Actif'), '${a?.activeMinutes ?? 0}', unit: 'MIN', size: 40),
        StatCell(context.t('Distance', 'Distance'), ((a?.distanceMeters ?? 0) / 1000).toStringAsFixed(1), unit: 'KM', size: 40),
        StatCell(context.t('Energy', 'Énergie'), '${(a?.kcal ?? 0).round()}', unit: 'KCAL', size: 40),
      ]),
      const SizedBox(height: 22),
      Text(context.t('RECENT', 'RÉCENT'), style: He.eyebrow()),
      for (final w in health.workouts.take(4)) WorkoutRow(w),
      if (health.workouts.isEmpty) EmptyNote(context.t('No workouts yet.', 'Aucun entraînement pour l’instant.')),
      const SizedBox(height: 40),
      PillButton(context.t('Start workout', 'Démarrer un entraînement'), onTap: () => pickWorkout(context)),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const HapticGlyph(null, color: He.ink2),
        Text(context.t('Or double-tap your band', 'Ou touchez deux fois le bracelet'), style: He.sans(16, color: He.ink2)),
      ]),
    ]);
  }
}

String workoutName(BuildContext c, WorkoutKind k) => switch (k) {
      WorkoutKind.run => c.t('Run', 'Course'),
      WorkoutKind.walk => c.t('Walk', 'Marche'),
      WorkoutKind.ride => c.t('Ride', 'Vélo'),
      WorkoutKind.poolSwim => c.t('Pool swim', 'Natation en piscine'),
      WorkoutKind.strength => c.t('Strength', 'Musculation'),
    };

IconData workoutIcon(WorkoutKind k) => switch (k) {
      WorkoutKind.poolSwim => Icons.waves_rounded,
      WorkoutKind.ride => Icons.directions_bike_rounded,
      WorkoutKind.strength => Icons.fitness_center_rounded,
      _ => Icons.architecture_rounded,
    };

class WorkoutRow extends StatelessWidget {
  const WorkoutRow(this.w, {super.key});
  final RecordedWorkout w;
  @override
  Widget build(BuildContext context) {
    final km = w.distanceM >= 50 ? '${(w.distanceM / 1000).toStringAsFixed(1)} KM · ' : '';
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSummaryScreen(w))),
      child: Container(
        height: 72,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: He.hairline))),
        child: Row(children: [
          SizedBox(
            width: 50,
            child: w.kind == WorkoutKind.run || w.kind == WorkoutKind.walk
                ? const Align(alignment: Alignment.centerLeft, child: NavIcon(NavGlyph.activity, color: He.ink2, size: 24))
                : Align(alignment: Alignment.centerLeft, child: Icon(workoutIcon(w.kind), color: He.ink2, size: 22)),
          ),
          Expanded(child: Text(workoutName(context, w.kind), style: He.sans(20))),
          Text('$km${mmss(w.duration)}', style: He.mono(15, weight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

Future<void> pickWorkout(BuildContext context) async {
  final kind = await showModalBottomSheet<WorkoutKind>(
    context: context,
    backgroundColor: He.bgEnd,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(He.gutter, 24, He.gutter, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.t('START A WORKOUT', 'DÉMARRER'), style: He.eyebrow()),
          const SizedBox(height: 8),
          for (final k in WorkoutKind.values)
            RowTile(label: workoutName(c, k), chevron: true, onTap: () => Navigator.pop(c, k)),
        ]),
      ),
    ),
  );
  if (kind != null && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveWorkoutScreen(kind: kind)));
  }
}
