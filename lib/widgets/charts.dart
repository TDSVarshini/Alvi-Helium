import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../theme/tokens.dart';

void _dotted(Canvas canvas, Offset a, Offset b, {Color color = He.ink4, double gap = 4}) {
  final p = Paint()
    ..color = color
    ..strokeWidth = 1;
  final len = (b - a).distance;
  final dir = (b - a) / len;
  for (double d = 0; d < len; d += gap) {
    canvas.drawCircle(a + dir * d, 0.6, p);
  }
}

/// Readiness / trial ring: grey track, coloured arc from 12 o'clock, end dot.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.fraction, required this.child, this.size = 290, this.color = He.teal, this.endDot = true, this.stroke = 4});
  final double fraction;
  final Widget child;
  final double size;
  final Color color;
  final bool endDot;
  final double stroke;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, f, child) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(f, color, endDot, stroke),
          child: SizedBox.square(dimension: size, child: Center(child: child)),
        ),
        child: child,
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.color, this.endDot, this.stroke);
  final double f;
  final Color color;
  final bool endDot;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 10;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = He.track);
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * f;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color);
    if (endDot && f > 0) {
      final a = start + sweep;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 11, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.f != f || old.color != color;
}

/// Four-lane hypnogram (awake / REM / light / deep) with time labels.
class Hypnogram extends StatelessWidget {
  const Hypnogram(this.night, {super.key, this.labels = const ['AWAKE', 'REM', 'LIGHT', 'DEEP']});
  final SleepNight night;
  final List<String> labels;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(double.infinity, 250), painter: _HypnoPainter(night, labels));
}

class _HypnoPainter extends CustomPainter {
  _HypnoPainter(this.night, this.labels);
  final SleepNight night;
  final List<String> labels;

  static const lanes = [SleepStage.awake, SleepStage.rem, SleepStage.light, SleepStage.deep];
  static const colors = {
    SleepStage.awake: He.awake,
    SleepStage.rem: He.rem,
    SleepStage.light: He.light,
    SleepStage.deep: He.deep,
  };

  @override
  void paint(Canvas canvas, Size s) {
    const left = 90.0, laneH = 50.0;
    final right = s.width;
    final t0 = night.start.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, night.end.millisecondsSinceEpoch - t0);
    double x(DateTime t) => left + (t.millisecondsSinceEpoch - t0) / span * (right - left);

    for (var i = 0; i < lanes.length; i++) {
      final cy = 12 + i * laneH;
      final tp = TextPainter(text: TextSpan(text: labels[i], style: He.eyebrow(size: 11.5)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(0, cy - tp.height / 2));
      _dotted(canvas, Offset(left, cy), Offset(right, cy));
    }
    for (final seg in night.segments) {
      final lane = lanes.indexOf(seg.stage);
      if (lane < 0) continue;
      final cy = 12 + lane * laneH;
      final x0 = x(seg.start), x1 = math.max(x(seg.end), x0 + 4);
      final h = seg.stage == SleepStage.awake ? 22.0 : 26.0;
      final w = seg.stage == SleepStage.awake ? math.min(5.0, x1 - x0) : x1 - x0;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x0, cy - h / 2, w, h), const Radius.circular(7)),
          Paint()..color = colors[seg.stage]!);
    }
    // Hour ticks: first full hour, middle, last.
    final ticks = <DateTime>[];
    var t = DateTime(night.start.year, night.start.month, night.start.day, night.start.hour + 1);
    while (t.isBefore(night.end)) {
      ticks.add(t);
      t = t.add(const Duration(hours: 1));
    }
    if (ticks.isEmpty) return;
    final shown = {ticks.first, ticks[ticks.length ~/ 2], ticks.last};
    for (final tick in shown) {
      final label = '${tick.hour.toString().padLeft(2, '0')}:00';
      final tp = TextPainter(text: TextSpan(text: label, style: He.mono(13)), textDirection: TextDirection.ltr)..layout();
      final dx = (x(tick) - tp.width / 2).clamp(left, right - tp.width);
      tp.paint(canvas, Offset(dx, 12 + 4 * laneH - 4));
    }
  }

  @override
  bool shouldRepaint(covariant _HypnoPainter old) => old.night != night;
}

/// Smooth-free polyline over time with dotted guides and an end dot.
class LineSeries extends StatelessWidget {
  const LineSeries({
    super.key,
    required this.values,
    this.color = He.heart,
    this.height = 120,
    this.min,
    this.max,
    this.guides = const [],
    this.guideLabels = false,
    this.endDot = true,
    this.band = false,
  });
  final List<double> values;
  final Color color;
  final double height;
  final double? min;
  final double? max;
  final List<double> guides;
  final bool guideLabels;
  final bool endDot;
  final bool band;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(double.infinity, height),
        painter: _LinePainter(values, color, min, max, guides, guideLabels, endDot, band),
      );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color, this.min, this.max, this.guides, this.guideLabels, this.endDot, this.band);
  final List<double> values;
  final Color color;
  final double? min, max;
  final List<double> guides;
  final bool guideLabels, endDot, band;

  @override
  void paint(Canvas canvas, Size s) {
    final left = guideLabels ? 46.0 : 0.0;
    final lo = min ?? (values.isEmpty ? 0 : values.reduce(math.min) - 5);
    final hi = max ?? (values.isEmpty ? 1 : values.reduce(math.max) + 5);
    double y(double v) => s.height - 6 - (v - lo) / math.max(1e-6, hi - lo) * (s.height - 12);
    if (band) {
      canvas.drawRect(Rect.fromLTWH(left, 0, s.width - left, s.height), Paint()..color = He.panel);
    }
    for (final g in guides) {
      _dotted(canvas, Offset(left + 4, y(g)), Offset(s.width, y(g)));
      if (guideLabels) {
        final tp = TextPainter(text: TextSpan(text: g.toStringAsFixed(0), style: He.mono(13)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(0, y(g) - tp.height / 2));
      }
    }
    if (values.length < 2) return;
    final dx = (s.width - left) / (values.length - 1);
    final path = Path()..moveTo(left, y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(left + i * dx, y(values[i]));
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round);
    if (endDot) canvas.drawCircle(Offset(s.width, y(values.last)), 5.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values;
}

/// Nightly deviation dots in a shaded band, latest highlighted.
class DeviationDots extends StatelessWidget {
  const DeviationDots(this.values, {super.key, this.range = 1});
  final List<double> values;
  final double range;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(double.infinity, 190), painter: _DotsPainter(values, range));
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.values, this.range);
  final List<double> values;
  final double range;
  @override
  void paint(Canvas canvas, Size s) {
    const left = 34.0;
    double y(double v) => s.height / 2 - (v / range).clamp(-1.2, 1.2) * (s.height / 2 - 16);
    for (final (v, label) in [(range, '+${range.toStringAsFixed(0)}'), (0.0, '0'), (-range, '-${range.toStringAsFixed(0)}')]) {
      final tp = TextPainter(text: TextSpan(text: label, style: He.mono(13)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }
    canvas.drawRect(Rect.fromLTRB(left, y(range * 0.45), s.width, y(-range * 0.45)), Paint()..color = He.panel);
    _dotted(canvas, Offset(left, y(0)), Offset(s.width, y(0)));
    if (values.isEmpty) return;
    final dx = values.length == 1 ? 0.0 : (s.width - left - 20) / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      final last = i == values.length - 1;
      canvas.drawCircle(Offset(left + 10 + i * dx, y(values[i])), last ? 8 : 3.6,
          Paint()..color = last ? He.warm : He.ink3);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.values != values;
}

/// Thin track with a filled portion and a dot; used for readiness factors.
class FactorBar extends StatelessWidget {
  const FactorBar(this.fraction, {super.key, this.color = He.teal});
  final double fraction;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 16,
        child: LayoutBuilder(builder: (_, c) {
          final x = c.maxWidth * fraction.clamp(0.02, 0.98);
          return Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 2, color: He.track),
            Container(height: 2, width: x, color: color),
            Positioned(left: x - 7, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
          ]);
        }),
      );
}

/// Seven vertical bars, last one highlighted (readiness history).
class WeekBars extends StatelessWidget {
  const WeekBars(this.values, this.labels, {super.key, this.color = He.teal});
  final List<double> values; // 0..100
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 160,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  width: i == values.length - 1 ? 4 : 3.5,
                  height: 20 + 100 * (values[i] / 100).clamp(0, 1),
                  decoration: BoxDecoration(
                    color: i == values.length - 1 ? color : He.ink4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                Text(labels[i], style: He.sans(14, color: i == values.length - 1 ? He.ink : He.ink3)),
              ]),
            ),
        ]),
      );
}

/// Step progress: hairline ticks above a green progress track with a dot.
class TickProgress extends StatelessWidget {
  const TickProgress(this.fraction, {super.key, this.color = He.move});
  final double fraction;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(double.infinity, 46), painter: _TickPainter(fraction.clamp(0, 1), color));
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.f, this.color);
  final double f;
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final tick = Paint()
      ..color = He.ink4
      ..strokeWidth = 1;
    const n = 36;
    for (var i = 0; i <= n; i++) {
      final x = s.width * i / n;
      canvas.drawLine(Offset(x, 4), Offset(x, 24), tick);
    }
    final y = s.height - 8;
    canvas.drawLine(Offset(0, y), Offset(s.width, y), Paint()
      ..color = He.track
      ..strokeWidth = 2.5);
    canvas.drawLine(Offset(0, y), Offset(s.width * f, y), Paint()
      ..color = color
      ..strokeWidth = 2.5);
    canvas.drawCircle(Offset(s.width * f, y), 11, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TickPainter old) => old.f != f;
}

/// Weekly trend line with grey dots and a highlighted latest point.
class TrendLine extends StatelessWidget {
  const TrendLine(this.values, {super.key, this.color = He.teal});
  final List<double> values;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(double.infinity, 120), painter: _TrendPainter(values, color));
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    _dotted(canvas, Offset(0, 8), Offset(s.width, 8));
    _dotted(canvas, Offset(0, s.height - 8), Offset(s.width, s.height - 8));
    if (values.length < 2) return;
    final lo = values.reduce(math.min) - 5, hi = values.reduce(math.max) + 5;
    Offset pt(int i) => Offset(12 + i * (s.width - 24) / (values.length - 1),
        s.height - 12 - (values[i] - lo) / (hi - lo) * (s.height - 24));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);
    for (var i = 0; i < values.length; i++) {
      final last = i == values.length - 1;
      canvas.drawCircle(pt(i), last ? 8 : 5, Paint()..color = last ? color : He.ink3);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.values != values;
}

/// Time-in-zone bars: "Z3 ───────── 22 MIN".
class ZoneBars extends StatelessWidget {
  const ZoneBars(this.minutes, {super.key});

  /// Minutes in Z5..Z1 order of display (keys 1..5).
  final Map<int, int> minutes;

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(1, minutes.values.fold(0, math.max));
    final zones = minutes.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(children: [
      for (final z in zones)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            SizedBox(width: 44, child: Text('Z$z', style: He.mono(15))),
            Expanded(
              child: LayoutBuilder(
                builder: (_, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(height: 2.5, width: c.maxWidth * 0.85 * minutes[z]! / maxV, color: He.heart),
                ),
              ),
            ),
            SizedBox(width: 80, child: Text('${minutes[z]} MIN', textAlign: TextAlign.right, style: He.mono(15))),
          ]),
        ),
    ]);
  }
}

/// Heart-zone progress: five segments, filled up to the current zone.
class ZoneSegments extends StatelessWidget {
  const ZoneSegments(this.zone, {super.key});
  final int zone;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 1; i <= 5; i++) ...[
          if (i > 1) const SizedBox(width: 10),
          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= zone ? He.heart : He.track, borderRadius: BorderRadius.circular(2)))),
        ],
      ]);
}
