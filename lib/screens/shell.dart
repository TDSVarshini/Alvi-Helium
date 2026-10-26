import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/glyphs.dart';
import 'activity.dart';
import 'heart.dart';
import 'sleep.dart';
import 'today.dart';
import 'workout.dart';
import 'you.dart';

/// The five tabs. A double-tap on the band starts a workout from anywhere.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<void>? _taps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final app = context.read<AppState>();
    _taps = app.doubleTaps.listen((_) {
      if (LiveWorkoutScreen.active || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const LiveWorkoutScreen(kind: WorkoutKind.run, startedByTap: true)));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => app.reconnect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) {
      context.read<AppState>().setForeground(state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (NavGlyph.today, context.t('Today', 'Aujourd’hui')),
      (NavGlyph.sleep, context.t('Sleep', 'Sommeil')),
      (NavGlyph.heart, context.t('Heart', 'Cœur')),
      (NavGlyph.activity, context.t('Activity', 'Activité')),
      (NavGlyph.you, context.t('You', 'Vous')),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [TodayTab(), SleepTab(), HeartTab(), ActivityTab(), YouTab()]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: He.bgEnd, border: Border(top: BorderSide(color: He.hairline))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 74,
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: Semantics(
                    selected: _tab == i,
                    button: true,
                    label: tabs[i].$2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _tab = i),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        NavIcon(tabs[i].$1, color: _tab == i ? He.ink : He.ink3),
                        const SizedBox(height: 6),
                        Text(tabs[i].$2,
                            style: He.sans(14.5, weight: _tab == i ? FontWeight.w700 : FontWeight.w400, color: _tab == i ? He.ink : He.ink3)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tab page body: gradient, pull to sync, padded list.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [He.bgStart, He.bgEnd], stops: [0, 0.35])),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: He.ink,
          onRefresh: () => app.ready ? app.syncNow() : app.reconnect(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(He.gutter, 28, He.gutter, 24),
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Shown when a tab has nothing yet (new user, ring not synced).
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(text, style: He.body(18, He.ink3)),
      );
}
