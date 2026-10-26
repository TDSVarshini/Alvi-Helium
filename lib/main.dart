import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/health_store.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_CA');
  await initializeDateFormatting('fr_CA');
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
  final prefs = await SharedPreferences.getInstance();
  final health = HealthStore(prefs);
  final app = AppState(prefs, health)..load();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: health),
    ],
    child: const HeliumApp(),
  ));
}

class HeliumApp extends StatelessWidget {
  const HeliumApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final french = app.prefs.french;
    return MaterialApp(
      title: 'ALVI Helium',
      debugShowCheckedModeBanner: false,
      theme: He.theme(),
      locale: Locale(french ? 'fr' : 'en', 'CA'),
      supportedLocales: const [Locale('en', 'CA'), Locale('fr', 'CA')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => Lang(french: french, child: child!),
      home: app.onboarded ? const Shell() : const WelcomeScreen(),
    );
  }
}
