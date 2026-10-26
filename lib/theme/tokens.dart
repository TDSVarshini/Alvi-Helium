import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours sampled from the ALVI Helium design. The canvas is a soft grey
/// gradient; colour is reserved for data (one hue per signal).
abstract final class He {
  static const bgStart = Color(0xFFD9D9D9);
  static const bgEnd = Color(0xFFE9E9E9);
  static const ink = Color(0xFF0A0A0A);
  static const ink2 = Color(0xFF333333);
  static const ink3 = Color(0xFF666666);
  static const ink4 = Color(0xFF9A9A9A);
  static const hairline = Color(0xFFC6C6C6);
  static const track = Color(0xFFC9C9C9);
  static const panel = Color(0x14000000);

  static const teal = Color(0xFF2E7F7A); // readiness, membership
  static const deep = Color(0xFF4351A8); // sleep stages
  static const rem = Color(0xFF6F79C8);
  static const light = Color(0xFF9DA4DC);
  static const awake = Color(0xFF8A8A8A);
  static const heart = Color(0xFFC85A4B);
  static const oxygen = Color(0xFF3F6FAE);
  static const warm = Color(0xFFB4702E); // skin temperature, weather
  static const move = Color(0xFF4E8A62); // activity

  static const gutter = 20.0;

  static TextStyle sans(double size,
          {FontWeight weight = FontWeight.w400, Color color = ink, double? spacing, double? height}) =>
      GoogleFonts.inter(
          fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing, height: height);

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w600, Color color = ink2}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color);

  /// Spaced small caps label, e.g. "LAST NIGHT".
  static TextStyle eyebrow({Color color = ink3, double size = 12.5}) =>
      sans(size, weight: FontWeight.w500, color: color, spacing: 2.4);

  static TextStyle headline([double size = 34]) =>
      sans(size, weight: FontWeight.w700, spacing: -0.6, height: 1.12);

  static TextStyle body([double size = 17, Color color = ink2]) =>
      sans(size, color: color, height: 1.4);

  /// Thin oversized numerals used for hero values.
  static TextStyle display(double size, {Color color = ink}) =>
      sans(size, weight: FontWeight.w300, color: color, spacing: -size * 0.03, height: 1.0);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: ink, surface: bgEnd, primary: ink),
      scaffoldBackgroundColor: bgEnd,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(textTheme: GoogleFonts.interTextTheme(base.textTheme));
  }
}
