import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../domain/insights.dart';
import '../format.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/health_store.dart';
import '../state/weather.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import 'shell.dart';

class TodayTab extends StatefulWidget {
  const TodayTab({super.key});
  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  late final Future<Weather?> _weather = fetchWeather();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final health = context.watch<HealthStore>();
    final night = health.lastNight;
    final r = health.readiness;
    final today = health.today;
    final temp = r?.tempDelta;

    return TabPage(children: [
      Row(children: [
        Expanded(child: Text(dayHeader(context, DateTime.now()), style: He.eyebrow(size: 14))),
        _ConnectionBadge(app: app, syncing: health.syncing),
      ]),
      const SizedBox(height: 28),
      FutureBuilder<Weather?>(
        future: _weather,
        builder: (_, s) => s.data == null ? const SizedBox(height: 8) : _WeatherLine(s.data!),
      ),
      const SizedBox(height: 18),
      Center(
        child: ScoreRing(
          fraction: (r?.score ?? 0) / 100,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.t('READINESS', 'DISPONIBILITÉ'), style: He.eyebrow(size: 14)),
            Text(r?.hasData == true ? '${r!.score}' : '—', style: He.display(120)),
            if (r?.hasData == true)
              UnderlineLink(context.t('See why', 'Pourquoi'), size: 17, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReadinessScreen()))),
          ]),
        ),
      ),
      const SizedBox(height: 26),
      if (r?.hasData == true) ...[
        Center(child: Eyebrow(readinessStatus(context, r!.score), dot: He.teal, color: He.ink2)),
        const SizedBox(height: 12),
        Text(readinessSentence(context, r), textAlign: TextAlign.center, style: He.body(22, He.ink)),
      ] else
        Text(
          context.t('Wear Helium to sleep tonight. Your first readiness arrives tomorrow morning.',
              'Portez Helium cette nuit. Votre première disponibilité arrive demain matin.'),
          textAlign: TextAlign.center,
          style: He.body(20, He.ink2),
        ),
      const SizedBox(height: 60),
      Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: He.hairline))),
        child: SizedBox(
          height: 104,
          child: Row(children: [
            _Band(night?.worn == true ? hm(night!.sleepMin) : '—', context.t('SLEEP', 'SOMMEIL')),
            const Hairline(vertical: true),
            _Band(night?.hrv?.round().toString() ?? '—', 'HRV'),
            const Hairline(vertical: true),
            _Band(today?.activity == null ? '—' : compact(today!.activity!.steps), context.t('STEPS', 'PAS')),
            const Hairline(vertical: true),
            _Band(temp == null ? '—' : '${signed(temp)}°', context.t('SKIN', 'PEAU')),
          ]),
        ),
      ),
    ]);
  }
}

class _Band extends StatelessWidget {
  const _Band(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(children: [
            FittedBox(child: Text(value, style: He.sans(34, weight: FontWeight.w300))),
            const SizedBox(height: 6),
            Text(label, style: He.eyebrow(size: 12)),
          ]),
        ),
      );
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.app, required this.syncing});
  final AppState app;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    if (syncing) {
      return Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: He.ink3)),
        const SizedBox(width: 8),
        Text(context.t('SYNCING', 'SYNCHRO'), style: He.eyebrow(size: 11)),
      ]);
    }
    if (app.battery != null && app.ready) {
      return Row(children: [
        BatteryGlyph(app.battery!.level),
        const SizedBox(width: 8),
        Text('${app.battery!.level}%', style: He.sans(16, weight: FontWeight.w600)),
      ]);
    }
    if (!app.paired) return Text(context.t('SAMPLE', 'EXEMPLE'), style: He.eyebrow(size: 11));
    return GestureDetector(
      onTap: app.reconnect,
      child: Text(
        app.connection == RingConnectionState.connecting ? context.t('CONNECTING', 'CONNEXION') : context.t('OFFLINE', 'HORS LIGNE'),
        style: He.eyebrow(size: 11),
      ),
    );
  }
}

class _WeatherLine extends StatelessWidget {
  const _WeatherLine(this.w);
  final Weather w;

  @override
  Widget build(BuildContext context) {
    final sky = w.snow
        ? context.t('Snow', 'Neige')
        : w.rain
            ? context.t('Rain', 'Pluie')
            : w.clear
                ? context.t('Clear', 'Dégagé')
                : context.t('Cloudy', 'Nuageux');
    final advice = w.rain || w.snow
        ? context.t('Wet out. A good day for an indoor session.', 'Temps humide. Bonne journée pour l’intérieur.')
        : w.tempC < 0
            ? context.t('Cold out. Warm up longer before effort.', 'Il fait froid. Échauffez-vous plus longtemps.')
            : w.tempC > 26
                ? context.t('Warm out. Hydrate and go early.', 'Il fait chaud. Hydratez-vous et partez tôt.')
                : context.t('Cool and dry. A good morning to run outside.', 'Frais et sec. Une belle matinée pour courir dehors.');
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(w.clear ? Icons.wb_sunny_outlined : Icons.cloud_outlined, color: He.warm, size: 22),
        const SizedBox(width: 10),
        Text('${w.tempC.round()}° · $sky', style: He.sans(20)),
      ]),
      const SizedBox(height: 4),
      Text(advice, textAlign: TextAlign.center, style: He.sans(16.5, color: He.ink2)),
    ]);
  }
}

String readinessStatus(BuildContext c, int score) => score >= 75
    ? c.t('READY FOR EFFORT', 'PRÊT POUR L’EFFORT')
    : score >= 60
        ? c.t('STEADY', 'STABLE')
        : c.t('EASE OFF TODAY', 'ALLEZ-Y DOUCEMENT');

String readinessSentence(BuildContext c, Readiness r) {
  if (r.tempDelta != null && r.tempDelta!.abs() >= 0.6) {
    return c.t('Your skin temperature shifted overnight. Keep today light and listen to your body.',
        'Votre température cutanée a changé cette nuit. Restez léger aujourd’hui.');
  }
  if (r.hrvDelta != null && r.hrvDelta! >= 3) {
    return r.score >= 75
        ? c.t('Your HRV rose overnight. A good day to push a little harder.', 'Votre VFC a augmenté cette nuit. Une bonne journée pour pousser un peu.')
        : c.t('Your HRV rose overnight. Recovery is on its way.', 'Votre VFC a augmenté cette nuit. La récupération progresse.');
  }
  if (r.hrvDelta != null && r.hrvDelta! <= -5) {
    return c.t('Your HRV dipped below your baseline. Favour easy movement today.', 'Votre VFC est sous votre référence. Privilégiez un effort léger.');
  }
  if (r.sleep < 0.6) {
    return c.t('A short night. An early bedtime will help more than a hard session.', 'Nuit courte. Un coucher tôt aidera plus qu’une séance intense.');
  }
  return r.score >= 75
      ? c.t('You recovered well. Effort will feel easier today.', 'Bonne récupération. L’effort sera plus facile aujourd’hui.')
      : c.t('Balanced signals. A normal day of training is fine.', 'Signaux équilibrés. Une journée normale convient.');
}

class ReadinessScreen extends StatelessWidget {
  const ReadinessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<HealthStore>();
    final r = health.readiness!;
    final fr = context.isFrench;
    final week = health.recent(7);
    final avg = Insights.mean(health.history.reversed.skip(1).take(14).where((n) => n.readiness > 0).map((n) => n.readiness.toDouble()));
    final diff = avg == null ? null : r.score - avg.round();
    final factors = [
      (context.t('Sleep', 'Sommeil'), r.sleep, factorLabel(r.sleep, french: fr)),
      (context.t('HRV balance', 'Équilibre VFC'), r.hrv, factorLabel(r.hrv, french: fr, hrv: true)),
      (context.t('Resting heart rate', 'Fréquence au repos'), r.restingHr, factorLabel(r.restingHr, french: fr)),
      (context.t('Recent training load', 'Charge récente'), r.load, factorLabel(r.load, french: fr)),
      (context.t('Skin temperature', 'Température cutanée'), r.temp, factorLabel(r.temp, french: fr, temp: true)),
    ];
    return DetailPage(title: context.t('Readiness', 'Disponibilité'), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${r.score}', style: He.display(150)),
        const Spacer(),
        if (diff != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text('${diff >= 0 ? '+' : '−'}${diff.abs()} ${context.t('VS AVG', 'VS MOY')}', style: He.mono(15, weight: FontWeight.w700)),
          ),
      ]),
      const SizedBox(height: 18),
      Text(readinessSentence(context, r), style: He.body(24, He.ink)),
      const SizedBox(height: 26),
      Text(context.t('WHAT SHAPED IT', 'CE QUI L’A FAÇONNÉE'), style: He.eyebrow()),
      for (final (label, f, word) in factors)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: He.hairline))),
          child: Column(children: [
            Row(children: [Expanded(child: Text(label, style: He.sans(19))), Text(word, style: He.sans(19, color: He.ink2))]),
            const SizedBox(height: 12),
            FactorBar(f),
          ]),
        ),
      const SizedBox(height: 28),
      Text(context.t('LAST 7 DAYS', '7 DERNIERS JOURS'), style: He.eyebrow()),
      const SizedBox(height: 14),
      WeekBars(
        [for (final n in week) (n?.readiness ?? 0).toDouble()],
        [for (var i = 6; i >= 0; i--) weekdayInitial(context, HealthStore.dateOf(i))],
      ),
      Disclaimer(context.t('Readiness is general wellness guidance, not medical advice.',
          'La disponibilité est un conseil de bien-être général, pas un avis médical.')),
    ]);
  }
}
