import 'package:flutter/widgets.dart';

/// Helium ships in English and French (Canada). Strings are written inline as
/// `t('English', 'Français')` so both languages stay side by side.
class Lang extends InheritedWidget {
  const Lang({super.key, required this.french, required super.child});

  final bool french;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Lang>()?.french ?? false;

  @override
  bool updateShouldNotify(Lang old) => old.french != french;
}

extension Tr on BuildContext {
  String t(String en, String fr) => Lang.of(this) ? fr : en;
  bool get isFrench => Lang.of(this);
}
