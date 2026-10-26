import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/haptics.dart';
import '../theme/tokens.dart';

/// The ALVI script mark: a rising curve, two dots and a "v" swash.
class AlviMark extends StatelessWidget {
  const AlviMark({super.key, this.width = 220});
  final double width;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, width * 0.42), painter: _AlviPainter());
}

class _AlviPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = He.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.022
      ..strokeCap = StrokeCap.round;
    double x(double v) => v * s.width;
    double y(double v) => v * s.height;
    final a = Path()
      ..moveTo(x(0.02), y(0.95))
      ..cubicTo(x(0.12), y(0.35), x(0.30), y(-0.05), x(0.42), y(0.55))
      ..cubicTo(x(0.47), y(0.85), x(0.52), y(0.92), x(0.68), y(0.9));
    final v = Path()
      ..moveTo(x(0.62), y(0.38))
      ..cubicTo(x(0.70), y(0.55), x(0.75), y(1.05), x(0.84), y(0.92))
      ..cubicTo(x(0.90), y(0.82), x(0.95), y(0.5), x(0.97), y(0.30));
    canvas.drawPath(a, p);
    canvas.drawPath(v, p);
    final dot = Paint()..color = He.ink;
    canvas.drawCircle(Offset(x(0.26), y(0.62)), s.width * 0.045, dot);
    canvas.drawCircle(Offset(x(1.0), y(0.05)), s.width * 0.04, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small mark that depicts a haptic pattern (dot, dots, bar, swell...).
class HapticGlyph extends StatelessWidget {
  const HapticGlyph(this.pattern, {super.key, this.color = He.ink});
  final HapticPattern? pattern; // null = the hollow "double-tap" ring
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(pattern == null ? 28 : 64, 22), painter: _HapticGlyphPainter(pattern, color));
}

class _HapticGlyphPainter extends CustomPainter {
  _HapticGlyphPainter(this.pattern, this.color);
  final HapticPattern? pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final fill = Paint()..color = color;
    final cy = s.height / 2;
    void dot(double x, double r) => canvas.drawCircle(Offset(x, cy), r, fill);
    void bar(double x, double w) => canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, cy - 5, w, 10), const Radius.circular(5)), fill);
    switch (pattern) {
      case null:
        canvas.drawCircle(Offset(9, cy), 7,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4);
      case HapticPattern.onePulse || HapticPattern.tick:
        dot(8, 7);
      case HapticPattern.twoPulses:
        dot(8, 7);
        dot(27, 7);
      case HapticPattern.longPulse:
        bar(0, 56);
      case HapticPattern.rising:
        dot(3, 3);
        dot(16, 4.5);
        dot(32, 6);
        dot(50, 8);
      case HapticPattern.swell:
        final p = Path()
          ..moveTo(0, s.height - 2)
          ..cubicTo(18, s.height - 2, 20, 2, 32, 2)
          ..cubicTo(44, 2, 46, s.height - 2, 64, s.height - 2);
        canvas.drawPath(
            p,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..strokeCap = StrokeCap.round);
      case HapticPattern.shortLong:
        dot(7, 7);
        bar(20, 36);
    }
  }

  @override
  bool shouldRepaint(covariant _HapticGlyphPainter old) => old.pattern != pattern || old.color != color;
}

enum NavGlyph { today, sleep, heart, activity, you }

/// Thin-line tab icons drawn to match the design.
class NavIcon extends StatelessWidget {
  const NavIcon(this.glyph, {super.key, this.color = He.ink3, this.size = 28});
  final NavGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _NavPainter(glyph, color));
}

class _NavPainter extends CustomPainter {
  _NavPainter(this.glyph, this.color);
  final NavGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = s.center(Offset.zero);
    final u = s.width / 24;
    switch (glyph) {
      case NavGlyph.today:
        canvas.drawCircle(c, 10 * u, p);
        canvas.drawCircle(c, 3 * u, Paint()..color = color);
      case NavGlyph.sleep:
        final moon = Path()
          ..addOval(Rect.fromCircle(center: c, radius: 9.5 * u));
        final cut = Path()..addOval(Rect.fromCircle(center: c.translate(5.5 * u, -4.5 * u), radius: 8 * u));
        canvas.drawPath(Path.combine(PathOperation.difference, moon, cut), p);
      case NavGlyph.heart:
        canvas.drawPath(
            Path()
              ..moveTo(1 * u, 13 * u)
              ..lineTo(7 * u, 13 * u)
              ..lineTo(10 * u, 7 * u)
              ..lineTo(14 * u, 18 * u)
              ..lineTo(17 * u, 12 * u)
              ..lineTo(23 * u, 12 * u),
            p);
      case NavGlyph.activity:
        canvas.drawPath(
            Path()
              ..moveTo(5 * u, 20 * u)
              ..cubicTo(5 * u, 4 * u, 19 * u, 4 * u, 19 * u, 20 * u),
            p);
      case NavGlyph.you:
        canvas.drawCircle(Offset(12 * u, 8 * u), 4.5 * u, p);
        canvas.drawPath(
            Path()
              ..moveTo(3 * u, 22 * u)
              ..cubicTo(3 * u, 14 * u, 21 * u, 14 * u, 21 * u, 22 * u),
            p);
    }
  }

  @override
  bool shouldRepaint(covariant _NavPainter old) => old.glyph != glyph || old.color != color;
}

/// Wrist band (straps through a core) or upper-arm band (curved straps).
class BandGlyph extends StatelessWidget {
  const BandGlyph({super.key, required this.upperArm, this.color = He.ink, this.size = 72});
  final bool upperArm;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _BandPainter(upperArm, color));
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.upperArm, this.color);
  final bool upperArm;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.04
      ..strokeCap = StrokeCap.round;
    final w = s.width, h = s.height;
    final core = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w / 2, h / 2), width: w * 0.62, height: h * 0.3), Radius.circular(h * 0.15));
    canvas.drawRRect(core, p);
    if (upperArm) {
      canvas.drawPath(
          Path()
            ..moveTo(w * 0.12, h * 0.08)
            ..quadraticBezierTo(w * -0.02, h * 0.5, w * 0.12, h * 0.92),
          p);
      canvas.drawPath(
          Path()
            ..moveTo(w * 0.88, h * 0.08)
            ..quadraticBezierTo(w * 1.02, h * 0.5, w * 0.88, h * 0.92),
          p);
    } else {
      canvas.drawLine(Offset(w * 0.12, 0), Offset(w * 0.12, h), p);
      canvas.drawLine(Offset(w * 0.88, 0), Offset(w * 0.88, h), p);
      canvas.drawCircle(Offset(w / 2, h / 2), w * 0.05, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) => old.upperArm != upperArm || old.color != color;
}

/// The core (pill with a dot) on a strap line, shown on "Your Helium".
class CoreGlyph extends StatelessWidget {
  const CoreGlyph({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 120,
        child: CustomPaint(painter: _CorePainter(), size: const Size(double.infinity, 120)),
      );
}

class _CorePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    canvas.drawCircle(c, 70, Paint()..shader = RadialGradient(colors: [He.ink.withValues(alpha: 0.05), He.ink.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: 70)));
    final line = Paint()
      ..color = He.ink4
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(c.dx - 120, c.dy), Offset(c.dx - 55, c.dy), line);
    canvas.drawLine(Offset(c.dx + 55, c.dy), Offset(c.dx + 120, c.dy), line);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 110, height: 52), const Radius.circular(26)),
        Paint()
          ..color = He.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4);
    canvas.drawCircle(c, 4.5, Paint()..color = He.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Concentric rings with a soft centre, behind the welcome logo.
class Ripples extends StatefulWidget {
  const Ripples({super.key, required this.child, this.size = 300});
  final Widget child;
  final double size;
  @override
  State<Ripples> createState() => _RipplesState();
}

class _RipplesState extends State<Ripples> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) => CustomPaint(painter: _RipplePainter(_c.value), child: child),
          child: Center(child: widget.child),
        ),
      );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    for (var i = 0; i < 3; i++) {
      final rad = r * (0.39 + 0.305 * i) * (1 + 0.012 * math.sin((t + i / 3) * 2 * math.pi));
      canvas.drawCircle(
          c,
          rad,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = He.ink.withValues(alpha: 0.28 - i * 0.07));
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.t != t;
}

/// Battery outline with fill, as in the Today header.
class BatteryGlyph extends StatelessWidget {
  const BatteryGlyph(this.level, {super.key});
  final int level;
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(30, 16), painter: _BatteryPainter(level));
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.level);
  final int level;
  @override
  void paint(Canvas canvas, Size s) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s.width - 3, s.height), const Radius.circular(4));
    canvas.drawRRect(body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = He.ink);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s.width - 2.5, s.height * 0.3, 2.5, s.height * 0.4), const Radius.circular(1)),
        Paint()..color = He.ink);
    final w = (s.width - 9) * (level.clamp(0, 100) / 100);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(3, 3, w, s.height - 6), const Radius.circular(2)),
        Paint()..color = level <= 15 ? He.heart : He.ink);
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter old) => old.level != level;
}
