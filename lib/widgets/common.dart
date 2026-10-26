import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme/tokens.dart';

/// The grey gradient canvas every screen sits on.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child, this.safeBottom = true});
  final Widget child;
  final bool safeBottom;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [He.bgStart, He.bgEnd], stops: [0, 0.35]),
        ),
        child: SafeArea(bottom: safeBottom, child: child),
      );
}

class PillButton extends StatelessWidget {
  const PillButton(this.label, {super.key, this.onTap, this.outlined = false, this.height = 56});
  final String label;
  final VoidCallback? onTap;
  final bool outlined;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.35,
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: outlined ? Colors.transparent : He.ink,
              borderRadius: BorderRadius.circular(height / 2),
              border: outlined ? Border.all(color: He.ink3, width: 1.2) : null,
            ),
            child: Text(label,
                style: He.sans(outlined ? 17 : 18,
                    weight: FontWeight.w600, color: outlined ? He.ink : Colors.white)),
          ),
        ),
      ),
    );
  }
}

class UnderlineLink extends StatelessWidget {
  const UnderlineLink(this.label, {super.key, this.onTap, this.size = 16});
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(label,
              style: He.sans(size, color: He.ink2).copyWith(
                  decoration: TextDecoration.underline,
                  decorationThickness: 1.4,
                  decorationColor: He.ink2)),
        ),
      );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.dot, this.color = He.ink3});
  final String text;
  final Color? dot;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null) ...[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 10),
        ],
        Flexible(child: Text(text.toUpperCase(), style: He.eyebrow(color: color))),
      ]);
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false});
  final bool vertical;
  @override
  Widget build(BuildContext context) => vertical
      ? Container(width: 1, color: He.hairline)
      : Container(height: 1, color: He.hairline);
}

/// Detail-page header: back chevron, centred eyebrow title, optional action.
class NavHeader extends StatelessWidget {
  const NavHeader(this.title, {super.key, this.trailing, this.onBack});
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Stack(alignment: Alignment.center, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: context.t('Back', 'Retour'),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: He.ink),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            ),
          ),
          Text(title.toUpperCase(), style: He.eyebrow(size: 13)),
          if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
        ]),
      );
}

/// A full-width row with label, optional subtitle, value and chevron.
class RowTile extends StatelessWidget {
  const RowTile({
    super.key,
    required this.label,
    this.sub,
    this.value,
    this.valueWidget,
    this.mono = false,
    this.chevron = false,
    this.onTap,
    this.height = 64,
    this.labelSize = 18,
  });
  final String label;
  final String? sub;
  final String? value;
  final Widget? valueWidget;
  final bool mono;
  final bool chevron;
  final VoidCallback? onTap;
  final double height;
  final double labelSize;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: He.hairline))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: He.sans(labelSize)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: He.sans(14.5, color: He.ink3)),
                ],
              ]),
            ),
            ?valueWidget,
            if (value != null)
              Text(value!, style: mono ? He.mono(15) : He.sans(17, color: He.ink2)),
            if (chevron) ...[
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded, color: He.ink3, size: 22),
            ],
          ]),
        ),
      );
}

/// The design's switch: solid black when on, outlined with grey knob when off.
class HeToggle extends StatelessWidget {
  const HeToggle({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? He.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: value ? He.ink : He.ink4, width: 1.2),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: value ? Colors.white : He.ink3, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      );
}

class PillChoice extends StatelessWidget {
  const PillChoice(this.label, {super.key, required this.selected, required this.onTap, this.compact = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 22),
          height: compact ? 46 : 48,
          constraints: compact ? const BoxConstraints(minWidth: 46) : null,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? He.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? He.ink : He.ink4, width: 1.1),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 0),
            child: Text(label,
                style: He.sans(16.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? Colors.white : He.ink2)),
          ),
        ),
      );
}

/// Pill segmented control (Soft / Medium / Strong).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 58,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(29),
          border: Border.all(color: He.hairline, width: 1.2),
        ),
        child: Row(children: [
          for (final e in options.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? He.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(e.value,
                      style: He.sans(16.5,
                          weight: e.key == value ? FontWeight.w600 : FontWeight.w400,
                          color: e.key == value ? Colors.white : He.ink2)),
                ),
              ),
            ),
        ]),
      );
}

/// Labelled value in a grid cell: "DEEP / 1:38".
class StatCell extends StatelessWidget {
  const StatCell(this.label, this.value, {super.key, this.unit, this.size = 34});
  final String label;
  final String value;
  final String? unit;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 8, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: He.eyebrow(size: 12)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(value, style: He.sans(size, weight: FontWeight.w300)),
              if (unit != null) ...[
                const SizedBox(width: 5),
                Text(unit!, style: He.sans(size * 0.42, color: He.ink3, spacing: 1)),
              ],
            ]),
          ),
        ]),
      );
}

/// Cells laid out in rows with hairline dividers, as in the design's stat bands.
class StatGrid extends StatelessWidget {
  const StatGrid(this.cells, {super.key, this.columns = 3});
  final List<Widget> cells;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += columns) {
      final row = cells.sublist(i, (i + columns).clamp(0, cells.length));
      rows.add(Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: He.hairline))),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const Hairline(vertical: true),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: j == 0 ? 0 : 16),
                  child: j < row.length ? row[j] : const SizedBox(),
                ),
              ),
            ],
          ]),
        ),
      ));
    }
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: He.hairline))),
      child: Column(children: rows),
    );
  }
}

/// Oversized hero number with a small unit: "68 bpm", "7 h 42 m".
class HeroValue extends StatelessWidget {
  const HeroValue(this.parts, {super.key, this.size = 120});

  /// Alternating value/unit pairs, e.g. ['7', 'h', '42', 'm'].
  final List<String> parts;
  final double size;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          for (var i = 0; i < parts.length; i++)
            if (i.isEven)
              Text(parts[i], style: He.display(size))
            else
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 14),
                child: Text(parts[i], style: He.sans(size * 0.3, color: He.ink3)),
              ),
        ]),
      );
}

/// Onboarding page: "STEP n OF 8", progress segments, eyebrow, title, body.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.step,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.eyebrowDot,
    required this.children,
    required this.footer,
    this.onBack,
    this.total = 7,
  });
  final int step;
  final int total;
  final String eyebrow;
  final Color? eyebrowDot;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget footer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: Column(children: [
            SizedBox(
              height: 56,
              child: Stack(alignment: Alignment.center, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: context.t('Back', 'Retour'),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                ),
                Text(context.t('STEP $step OF $total', 'ÉTAPE $step SUR $total'), style: He.eyebrow(size: 13)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(He.gutter, 8, He.gutter, 0),
              child: Row(children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: Container(height: 2, color: i < step ? He.ink : He.track)),
                ],
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(He.gutter, 24, He.gutter, 24),
                children: [
                  Eyebrow(eyebrow, dot: eyebrowDot),
                  const SizedBox(height: 12),
                  Text(title, style: He.headline()),
                  if (subtitle != null) ...[
                    const SizedBox(height: 12),
                    Text(subtitle!, style: He.body()),
                  ],
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(He.gutter, 0, He.gutter, 16), child: footer),
          ]),
        ),
      );
}

/// Standard scrollable detail page with a [NavHeader].
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.title, required this.children, this.footer, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? footer;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: Column(children: [
            NavHeader(title, trailing: trailing),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(He.gutter, 12, He.gutter, 24),
                children: children,
              ),
            ),
            if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(He.gutter, 0, He.gutter, 16), child: footer),
          ]),
        ),
      );
}

class Disclaimer extends StatelessWidget {
  const Disclaimer(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Text(text, style: He.sans(14.5, color: He.ink3, height: 1.45)),
      );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: He.sans(15, color: Colors.white)),
      backgroundColor: He.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
}
