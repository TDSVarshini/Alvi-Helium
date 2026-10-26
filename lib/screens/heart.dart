import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../domain/insights.dart';
import '../domain/models.dart';
import '../format.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/health_store.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'shell.dart';

class HeartTab extends StatefulWidget {
  const HeartTab({super.key});
  @override
  State<HeartTab> createState() => _HeartTabState();
}

class _HeartTabState extends State<HeartTab> {
  bool _measuring = false;

  Future<void> _measure(AppState app) async {
    setState(() => _measuring = true);
    try {
      final r = await app.ring.measure(MeasurementType.heartRate);
      app.health.addLiveHeartRate(r.value);
    } catch (e) {
      if (mounted) toast(context, context.t('No reading. Check the band sits snugly.', 'Aucune mesure. Vérifiez l’ajustement du bracelet.'));
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final health = context.watch<HealthStore>();
    final d = health.today;
    final night = health.lastNight;
    final hr = d?.heartRate ?? const <Sample>[];
    final latest = hr.lastOrNull;
    final daytime = hr.where((s) => s.time.hour >= 8).map((s) => s.value);
    final dayAvg = Insights.mean(daytime);
    final values = hr.map((s) => s.value).toList();
    final temp = health.readiness?.tempDelta;

    String calm() {
      if (latest == null || dayAvg == null) return '';
      final diff = (dayAvg - latest.value).round();
      if (diff >= 3) return context.t('Calm and steady, ${_words(context, diff)} below your daytime average.', 'Calme et régulier, $diff sous votre moyenne de jour.');
      if (diff <= -10) return context.t('Elevated, ${-diff} above your daytime average.', 'Élevé, ${-diff} au-dessus de votre moyenne de jour.');
      return context.t('Right around your daytime average.', 'Proche de votre moyenne de jour.');
    }

    return TabPage(children: [
      Row(children: [
        Expanded(child: Text(context.t('HEART', 'CŒUR'), style: He.eyebrow(size: 14))),
        if (latest != null) Text(agoText(context, latest.time), style: He.mono(14, weight: FontWeight.w700)),
      ]),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: app.ready && !_measuring ? () => _measure(app) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(child: HeroValue([latest == null ? '—' : latest.value.round().toString(), 'bpm'], size: 140)),
          if (_measuring)
            const Padding(padding: EdgeInsets.only(left: 8, bottom: 30), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: He.heart))),
        ]),
      ),
      const SizedBox(height: 12),
      Text(calm(), style: He.body(24, He.ink)),
      const SizedBox(height: 26),
      Row(children: [
        Expanded(child: Text(context.t('TODAY', 'AUJOURD’HUI'), style: He.eyebrow())),
        if (values.isNotEmpty)
          Text('${values.reduce(math.min).round()} — ${values.reduce(math.max).round()}', style: He.mono(15, weight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12),
      LineSeries(values: _downsample(values, 48), guides: values.isEmpty ? const [] : [values.reduce(math.min) - 4, values.reduce(math.max) + 4], height: 130),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('00:00', style: He.mono(13)),
        Text('12:00', style: He.mono(13)),
        Text(context.t('NOW', 'MAINT.'), style: He.mono(13)),
      ]),
      const SizedBox(height: 20),
      StatGrid(columns: 2, [
        StatCell(context.t('Resting', 'Au repos'), night?.restingHr?.round().toString() ?? '—', unit: 'bpm', size: 52),
        StatCell(context.t('HRV', 'VFC'), night?.hrv?.round().toString() ?? '—', unit: 'ms', size: 52),
      ]),
      RowTile(
        label: context.t('Zone minutes this week', 'Minutes en zone cette semaine'),
        value: '${_zoneMinutes(health, app.profile.maxHr)}',
        chevron: true,
        height: 84,
      ),
      RowTile(
        label: context.t('Oxygen and breathing', 'Oxygène et respiration'),
        value: night?.spo2 == null ? '—' : '${night!.spo2!.round()}%',
        chevron: true,
        height: 84,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OxygenScreen())),
      ),
      RowTile(
        label: context.t('Skin temperature', 'Température cutanée'),
        value: temp == null ? '—' : '${signed(temp)} °C',
        chevron: true,
        height: 84,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SkinTempScreen())),
      ),
    ]);
  }

  String _words(BuildContext c, int n) {
    const en = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
    return !c.isFrench && n <= 10 ? en[n] : '$n';
  }

  static List<double> _downsample(List<double> v, int n) {
    if (v.length <= n) return v;
    final step = v.length / n;
    return [for (var i = 0; i < n; i++) Insights.mean(v.sublist((i * step).floor(), ((i + 1) * step).floor().clamp(0, v.length)))!];
  }

  /// Minutes at or above 60% of max HR in the last 7 days (recent days only).
  int _zoneMinutes(HealthStore h, int maxHr) {
    var total = 0;
    for (var i = 0; i < 7; i++) {
      final s = h.day(i)?.heartRate ?? const <Sample>[];
      for (var j = 1; j < s.length; j++) {
        if (s[j].value >= maxHr * 0.6) total += s[j].time.difference(s[j - 1].time).inMinutes.clamp(0, 10);
      }
    }
    return total;
  }
}

class OxygenScreen extends StatelessWidget {
  const OxygenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<HealthStore>();
    final d = health.today;
    final spo2 = Insights.nightly(d?.spo2 ?? const [], d?.sleep).where((v) => v >= 80).toList();
    final resp = health.recent(30).map((n) => n?.respRate).whereType<double>().toList();
    final avg = Insights.mean(spo2);
    final lo = spo2.isEmpty ? null : spo2.reduce(math.min), hi = spo2.isEmpty ? null : spo2.reduce(math.max);
    return DetailPage(title: context.t('Oxygen and breathing', 'Oxygène et respiration'), children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('BLOOD OXYGEN', 'OXYGÈNE SANGUIN'), style: He.eyebrow()),
              const SizedBox(height: 10),
              HeroValue([avg == null ? '—' : '${avg.round()}', '%'], size: 96),
              const SizedBox(height: 14),
              Text(lo == null ? '' : '${context.t('RANGE', 'PLAGE')} ${lo.round()}–${hi!.round()}', style: He.mono(15, weight: FontWeight.w700)),
            ]),
          ),
          const Hairline(vertical: true),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('BREATHS', 'RESPIRATIONS'), style: He.eyebrow()),
              const SizedBox(height: 10),
              HeroValue([d?.respiratoryRate?.toStringAsFixed(1) ?? '—', '/min'], size: 96),
              const SizedBox(height: 14),
              Text(context.t('OVERNIGHT AVG', 'MOY. DE NUIT'), style: He.mono(15, weight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 26),
      Text(
        spo2.isEmpty
            ? context.t('No overnight oxygen readings yet.', 'Aucune mesure d’oxygène nocturne pour l’instant.')
            : (lo! >= 92
                ? context.t('Breathing was steady all night.', 'La respiration a été régulière toute la nuit.')
                : context.t('A few dips overnight. Fit and position can affect readings.', 'Quelques baisses cette nuit. L’ajustement peut influencer les mesures.')),
        style: He.body(24, He.ink),
      ),
      const SizedBox(height: 22),
      Text(context.t('BLOOD OXYGEN · OVERNIGHT', 'OXYGÈNE · NUIT'), style: He.eyebrow()),
      const SizedBox(height: 12),
      LineSeries(values: spo2, color: He.oxygen, min: 89, max: 101, guides: const [90, 95, 100], guideLabels: true, endDot: false, height: 170),
      const SizedBox(height: 22),
      Text(context.t('BREATHING RATE · 30 NIGHTS', 'RESPIRATION · 30 NUITS'), style: He.eyebrow()),
      const SizedBox(height: 12),
      resp.length < 2
          ? Text(context.t('Breathing rate appears once your band reports it.', 'Le rythme respiratoire apparaîtra quand le bracelet le fournira.'), style: He.sans(15, color: He.ink3))
          : LineSeries(values: resp, color: He.oxygen, band: true, endDot: false, height: 46),
      Disclaimer(context.t(
          'General wellness only. Not intended to diagnose sleep apnea or any medical condition. Talk to a health professional about any concerns.',
          'Bien-être général seulement. Ne vise pas à diagnostiquer l’apnée du sommeil ni aucune condition médicale. Consultez un professionnel de la santé au besoin.')),
    ]);
  }
}

class SkinTempScreen extends StatelessWidget {
  const SkinTempScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<HealthStore>();
    final temps = [for (final n in health.recent(30).whereType<NightSummary>()) ?n.temp];
    final base = Insights.mean(temps);
    final devs = base == null ? <double>[] : [for (final t in temps) t - base];
    final last = health.readiness?.tempDelta;
    return DetailPage(title: context.t('Skin temperature', 'Température cutanée'), children: [
      Text(context.t('OVERNIGHT VS YOUR BASELINE', 'NUIT VS VOTRE RÉFÉRENCE'), style: He.eyebrow()),
      const SizedBox(height: 8),
      HeroValue([last == null ? '—' : signed(last), '°C'], size: 150),
      const SizedBox(height: 28),
      Text(
        last == null
            ? context.t('Your baseline forms over a few nights of wear.', 'Votre référence se forme après quelques nuits.')
            : last.abs() < 0.5
                ? context.t('Within your normal range. Helium tracks change, not your exact temperature.',
                    'Dans votre plage normale. Helium suit les variations, pas la température exacte.')
                : context.t('Outside your usual range. Rest, alcohol, a warm room or illness can all shift it.',
                    'Hors de votre plage habituelle. Repos, alcool, chambre chaude ou maladie peuvent l’influencer.'),
        style: He.body(24, He.ink),
      ),
      const SizedBox(height: 26),
      DeviationDots(devs),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(context.t('30 NIGHTS AGO', 'IL Y A 30 NUITS'), style: He.mono(14, weight: FontWeight.w700)),
        Text(context.t('LAST NIGHT', 'HIER SOIR'), style: He.mono(14, weight: FontWeight.w700)),
      ]),
      const SizedBox(height: 20),
      const Hairline(),
      RowTile(
        label: context.t('Cycle insights', 'Analyses du cycle'),
        sub: context.t('Optional and private. Coming in an app update.', 'Facultatif et privé. Bientôt dans une mise à jour.'),
        valueWidget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: He.ink3), borderRadius: BorderRadius.circular(6)),
          child: Text(context.t('SOON', 'BIENTÔT'), style: He.eyebrow(size: 12, color: He.ink2)),
        ),
      ),
      Disclaimer(context.t('Skin temperature is not body temperature and can\'t detect fever or illness. General wellness only.',
          'La température cutanée n’est pas la température corporelle et ne détecte ni fièvre ni maladie. Bien-être général seulement.')),
    ]);
  }
}
