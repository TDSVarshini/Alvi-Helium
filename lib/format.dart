import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'l10n.dart';

String two(int v) => v.toString().padLeft(2, '0');

/// 462 → "7:42"
String hm(int minutes) => '${minutes ~/ 60}:${two(minutes % 60)}';

/// DateTime → "22:48"
String clock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// minutes after midnight → "06:30"
String clockMin(int m) => '${two((m ~/ 60) % 24)}:${two(m % 60)}';

/// Duration → "42:10" or "1:02:10"
String mmss(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}'.replaceFirst(RegExp(r'^0(?=\d:)'), '');
}

String thousands(BuildContext c, num v) => NumberFormat.decimalPattern(c.isFrench ? 'fr_CA' : 'en_CA').format(v);

/// 5620 → "5.6k"
String compact(num v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);

String signed(double v, [int digits = 1]) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(digits)}';

/// "TUESDAY · 14 OCTOBER"
String dayHeader(BuildContext c, DateTime d) {
  final loc = c.isFrench ? 'fr_CA' : 'en_CA';
  return '${DateFormat.EEEE(loc).format(d)} · ${DateFormat('d MMMM', loc).format(d)}'.toUpperCase();
}

/// "MON 13 OCT"
String shortDate(BuildContext c, DateTime d) =>
    DateFormat('EEE d MMM', c.isFrench ? 'fr_CA' : 'en_CA').format(d).replaceAll('.', '').toUpperCase();

String monthName(BuildContext c, DateTime d) => DateFormat.MMMM(c.isFrench ? 'fr_CA' : 'en_CA').format(d).toUpperCase();

String weekdayInitial(BuildContext c, DateTime d) =>
    DateFormat.EEEEE(c.isFrench ? 'fr_CA' : 'en_CA').format(d).toUpperCase();

String agoText(BuildContext c, DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return c.t('MEASURED JUST NOW', 'MESURÉ À L’INSTANT');
  if (m < 60) return c.t('MEASURED $m MIN AGO', 'MESURÉ IL Y A $m MIN');
  return c.t('MEASURED AT ${clock(t)}', 'MESURÉ À ${clock(t)}');
}
