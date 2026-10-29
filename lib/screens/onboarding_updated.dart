import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qring_sdk/qring_sdk.dart';

import '../domain/haptics.dart';
import '../domain/models.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/backup_io.dart';
import '../state/permissions.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import 'shell.dart';

void _push(BuildContext c, Widget page) =>
    Navigator.of(c).push(MaterialPageRoute(builder: (_) => page));

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    Widget lang(String code, bool fr) => GestureDetector(
      onTap: () => app.setFrench(fr),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          code,
          style: He.sans(
            17,
            weight: FontWeight.w600,
            spacing: 2.4,
            color: app.prefs.french == fr ? He.ink : He.ink3,
          ),
        ),
      ),
    );

    return Scaffold(
      body: Backdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: He.gutter),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [lang('EN', false), lang('FR', true)],
                ),
              ),
              const Spacer(),
              const Ripples(size: 300, child: AlviMark(width: 150)),
              const Spacer(),
              Text(
                context.t(
                  'Wear less.\nKnow more.',
                  'Portez moins.\nSachez plus.',
                ),
                textAlign: TextAlign.center,
                style: He.headline(46),
              ),
              const SizedBox(height: 22),
              for (final line in [
                context.t('Nothing to look at.', 'Rien à regarder.'),
                context.t(
                  'A touch when it matters.',
                  'Une touche quand ça compte.',
                ),
                context.t(
                  'A morning brief that reads your night.',
                  'Un bilan matinal qui lit votre nuit.',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    line,
                    textAlign: TextAlign.center,
                    style: He.body(18),
                  ),
                ),
              const Spacer(),
              PillButton(
                context.t('Get started', 'Commencer'),
                onTap: () => _push(context, const LanguageStep()),
              ),
              const SizedBox(height: 14),
              Center(
                child: UnderlineLink(
                  context.t('I already have an account', 'J’ai déjà un compte'),
                  size: 15,
                  onTap: () {
                    toast(
                      context,
                      context.t(
                        'Account sign-in is not available yet.',
                        'La connexion au compte n’est pas encore disponible.',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'ALVI INTELLECTS INC. · ONTARIO',
                style: He.eyebrow(size: 12),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageStep extends StatelessWidget {
  const LanguageStep({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.prefs;
    Widget option(String label, bool fr) => InkWell(
      onTap: () => app.setFrench(fr),
      child: Container(
        height: 84,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: He.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: He.sans(
                  34,
                  weight: FontWeight.w300,
                  color: p.french == fr ? He.ink : He.ink3,
                ),
              ),
            ),
            Icon(
              p.french == fr
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: p.french == fr ? He.ink : He.ink3,
              size: 30,
            ),
          ],
        ),
      ),
    );
    return StepScaffold(
      step: 1,
      eyebrow: 'LANGUAGE · LANGUE',
      title: context.t('Choose your\nlanguage.', 'Choisissez votre\nlangue.'),
      footer: PillButton(
        context.t('Continue', 'Continuer'),
        onTap: () => _push(context, const PrivacyStep()),
      ),
      children: [
        const Hairline(),
        option('English', false),
        option('Français', true),
        const SizedBox(height: 28),
        Text(
          context.t('REGION AND UNITS', 'RÉGION ET UNITÉS'),
          style: He.eyebrow(),
        ),
        const SizedBox(height: 8),
        const Hairline(),
        RowTile(
          label: context.t('Region', 'Région'),
          value: p.region,
          height: 84,
        ),
        RowTile(
          label: context.t('Units', 'Unités'),
          value: p.metric
              ? context.t('Metric · kg, cm, km', 'Métrique · kg, cm, km')
              : context.t('Imperial · lb, in, mi', 'Impérial · lb, po, mi'),
          height: 84,
          onTap: () {
            p.metric = !p.metric;
            app.save();
          },
        ),
        RowTile(
          label: context.t('Temperature', 'Température'),
          value: p.celsius ? '°C' : '°F',
          height: 84,
          onTap: () {
            p.celsius = !p.celsius;
            app.save();
          },
        ),
      ],
    );
  }
}

class PrivacyStep extends StatelessWidget {
  const PrivacyStep({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return StepScaffold(
      step: 2,
      eyebrow: context.t('PRIVACY', 'CONFIDENTIALITÉ'),
      title: context.t('Your body.\nYour data.', 'Votre corps.\nVos données.'),
      subtitle: context.t(
        'Helium has no account and no cloud. Everything stays on this phone unless you export it.',
        'Helium n’a ni compte ni nuage. Tout reste sur ce téléphone, sauf si vous l’exportez.',
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(
              'Consent under PIPEDA and Québec Law 25. Privacy officer: [CONTACT]. Read the full Privacy Policy.',
              'Consentement selon la LPRPDE et la Loi 25 du Québec. Responsable de la protection : [CONTACT]. Lire la Politique complète.',
            ),
            style: He.sans(14.5, color: He.ink3, height: 1.45),
          ),
          const SizedBox(height: 18),
          PillButton(
            context.t('I agree', 'J’accepte'),
            onTap: () {
              app.save();
              _push(context, const AboutYouStep());
            },
          ),
        ],
      ),
      children: const [PrivacyChoices()],
    );
  }
}

/// What Helium stores and where; reused from You › Privacy and data.
class PrivacyChoices extends StatelessWidget {
  const PrivacyChoices({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(String title, String sub, {String? tag}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: He.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: title, style: He.sans(19)),
                if (tag != null)
                  TextSpan(text: '   $tag', style: He.eyebrow(size: 11.5)),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(sub, style: He.sans(15, color: He.ink3)),
        ],
      ),
    );
    return Column(
      children: [
        const Hairline(),
        row(
          context.t('Health signals', 'Signaux de santé'),
          context.t(
            'Heart, sleep, motion and temperature from your band, needed for your insights',
            'Cœur, sommeil, mouvement et température du bracelet, nécessaires à vos analyses',
          ),
          tag: context.t('REQUIRED', 'REQUIS'),
        ),
        row(
          context.t(
            'Nothing leaves your phone',
            'Rien ne quitte votre téléphone',
          ),
          context.t(
            'No account, no analytics, no uploads. Weather uses your rough location only.',
            'Aucun compte, aucune analyse, aucun envoi. La météo utilise seulement votre position approximative.',
          ),
        ),
        row(
          context.t('You hold the backup', 'Vous gardez la sauvegarde'),
          context.t(
            'Export a file in You › Privacy and data to move to a new phone.',
            'Exportez un fichier dans Vous › Confidentialité pour changer de téléphone.',
          ),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 20, color: He.ink2),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                context.t(
                  'STORED ON THIS PHONE · APP-PRIVATE STORAGE',
                  'STOCKÉ SUR CE TÉLÉPHONE · STOCKAGE PRIVÉ',
                ),
                style: He.mono(14.5, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AboutYouStep extends StatefulWidget {
  const AboutYouStep({super.key, this.editing = false});
  final bool editing;
  @override
  State<AboutYouStep> createState() => _AboutYouStepState();
}

class _AboutYouStepState extends State<AboutYouStep> {
  late final app = context.read<AppState>();
  late final name = TextEditingController(text: app.profile.name);
  late final year = TextEditingController(text: '${app.profile.birthYear}');
  late final height = TextEditingController(text: '${app.profile.heightCm}');
  late final weight = TextEditingController(text: '${app.profile.weightKg}');

  @override
  void dispose() {
    for (final c in [name, year, height, weight]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get valid {
    final y = int.tryParse(year.text) ?? 0,
        h = int.tryParse(height.text) ?? 0,
        w = int.tryParse(weight.text) ?? 0;
    return name.text.trim().isNotEmpty &&
        y > 1900 &&
        y <= DateTime.now().year - 13 &&
        h >= 100 &&
        h <= 250 &&
        w >= 30 &&
        w <= 300;
  }

  void submit() {
    final p = app.profile
      ..name = name.text.trim()
      ..birthYear = int.parse(year.text)
      ..heightCm = int.parse(height.text)
      ..weightKg = int.parse(weight.text);
    if (!widget.editing) p.memberSince = DateTime.now();
    app.save();
    if (app.ready) {
      app.ring
          .setUserProfile(
            male: p.sex == Sex.male,
            age: p.age,
            heightCm: p.heightCm,
            weightKg: p.weightKg,
            metric: app.prefs.metric,
          )
          .catchError((_) {});
    }
    widget.editing ? Navigator.pop(context) : _push(context, const WakeStep());
  }

  Widget field(
    String label,
    TextEditingController c, {
    String? unit,
    bool number = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: He.eyebrow()),
      TextField(
        controller: c,
        onChanged: (_) => setState(() {}),
        keyboardType: number ? TextInputType.number : TextInputType.name,
        textCapitalization: TextCapitalization.words,
        inputFormatters: number
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ]
            : null,
        style: He.sans(34, weight: FontWeight.w300),
        decoration: InputDecoration(
          isDense: true,
          border: const UnderlineInputBorder(
            borderSide: BorderSide(color: He.hairline),
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: He.hairline),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: He.ink),
          ),
          suffix: unit == null ? null : Text(unit, style: He.eyebrow(size: 14)),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = app.profile;
    final goals = {
      Goal.sleep: context.t('Sleep better', 'Mieux dormir'),
      Goal.recover: context.t('Recover faster', 'Récupérer plus vite'),
      Goal.train: context.t('Train smarter', 'S’entraîner mieux'),
      Goal.stress: context.t('Manage stress', 'Gérer le stress'),
      Goal.move: context.t('Move more', 'Bouger plus'),
    };
    return StepScaffold(
      step: 3,
      eyebrow: context.t('ABOUT YOU', 'À PROPOS DE VOUS'),
      title: context.t('A few basics.', 'Quelques bases.'),
      subtitle: context.t(
        'They calibrate your baselines. Nothing here is shared.',
        'Elles calibrent vos références. Rien n’est partagé.',
      ),
      footer: PillButton(
        widget.editing
            ? context.t('Save', 'Enregistrer')
            : context.t('Continue', 'Continuer'),
        onTap: valid ? submit : null,
      ),
      children: [
        const Hairline(),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: field(
                context.t('FIRST NAME', 'PRÉNOM'),
                name,
                number: false,
              ),
            ),
            const SizedBox(width: 34),
            Expanded(
              child: field(
                context.t('YEAR OF BIRTH', 'ANNÉE DE NAISSANCE'),
                year,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: field(context.t('HEIGHT', 'TAILLE'), height, unit: 'CM'),
            ),
            const SizedBox(width: 34),
            Expanded(
              child: field(context.t('WEIGHT', 'POIDS'), weight, unit: 'KG'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          context.t(
            'SEX AT BIRTH · FOR PHYSIOLOGY',
            'SEXE À LA NAISSANCE · PHYSIOLOGIE',
          ),
          style: He.eyebrow(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (s, label) in [
              (Sex.female, context.t('Female', 'Femme')),
              (Sex.male, context.t('Male', 'Homme')),
              (
                Sex.unspecified,
                context.t('Prefer not to say', 'Je préfère ne pas répondre'),
              ),
            ])
              PillChoice(
                label,
                selected: p.sex == s,
                onTap: () => setState(() => p.sex = s),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          context.t(
            'WHAT SHOULD HELIUM HELP WITH?',
            'EN QUOI HELIUM PEUT-IL AIDER?',
          ),
          style: He.eyebrow(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final e in goals.entries)
              PillChoice(
                e.value,
                selected: p.goals.contains(e.key),
                onTap: () => setState(() {
                  p.goals.contains(e.key)
                      ? p.goals.remove(e.key)
                      : p.goals.add(e.key);
                }),
              ),
          ],
        ),
      ],
    );
  }
}

class WakeStep extends StatelessWidget {
  const WakeStep({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = [
      context.t(
        'Place the Helium core on its charger.',
        'Placez le cœur Helium sur son chargeur.',
      ),
      context.t(
        'Wait for one soft pulse. It\'s awake.',
        'Attendez une douce pulsation. Il est réveillé.',
      ),
      context.t(
        'Keep your phone within one metre.',
        'Gardez votre téléphone à moins d’un mètre.',
      ),
    ];
    return StepScaffold(
      step: 4,
      eyebrow: context.t('PAIR YOUR BAND', 'JUMELEZ VOTRE BRACELET'),
      title: context.t('Wake the core.', 'Réveillez le cœur.'),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PillButton(
            context.t('I felt the pulse', 'J’ai senti la pulsation'),
            onTap: () async {
              if (!await ensureBluetoothPermissions()) {
                if (context.mounted) {
                  toast(
                    context,
                    context.t(
                      'Helium needs Bluetooth permission to find your band.',
                      'Helium a besoin du Bluetooth pour trouver votre bracelet.',
                    ),
                  );
                }
                return;
              }
              if (context.mounted) _push(context, const FoundStep());
            },
          ),
          const SizedBox(height: 6),
          UnderlineLink(
            context.t('Need help?', 'Besoin d’aide?'),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: He.bgEnd,
              builder: (_) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.t(
                    'If you felt nothing, leave the core on the charger for ten minutes, then try again. Make sure Bluetooth is on and the band is not paired to another phone.',
                    'Si vous n’avez rien senti, laissez le cœur sur le chargeur dix minutes, puis réessayez. Vérifiez que le Bluetooth est activé et que le bracelet n’est pas jumelé à un autre téléphone.',
                  ),
                  style: He.body(),
                ),
              ),
            ),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 30),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 34),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Text('0${i + 1}', style: He.mono(18, color: He.ink3)),
                ),
                Expanded(
                  child: Text(
                    steps[i],
                    style: He.sans(24, weight: FontWeight.w300, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Scans, connects to the strongest band so it can pulse its code, and asks
/// the user to confirm it is theirs.
class FoundStep extends StatefulWidget {
  const FoundStep({super.key});
  @override
  State<FoundStep> createState() => _FoundStepState();
}

class _FoundStepState extends State<FoundStep> {
  late final app = context.read<AppState>();
  final _rejected = <String>{};
  final _seen = <ScannedRing>[];
  ScannedRing? _candidate;
  StreamSubscription<ScannedRing>? _scanSub;
  StreamSubscription<RingEvent>? _evSub;
  Timer? _deadline;
  bool _scanning = true;
  bool _linked = false;

  @override
  void initState() {
    super.initState();
    _evSub = app.ring.events.listen((e) {
      if (e is ConnectionEvent &&
          e.state == RingConnectionState.ready &&
          _candidate != null) {
        setState(() => _linked = true);
        // Short, long, short: the code the user is asked to feel.
        Future<void>(() async {
          await app.ring.vibrate(on: const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await app.ring.vibrate(on: const Duration(milliseconds: 700));
          await Future<void>.delayed(const Duration(milliseconds: 1000));
          await app.ring.vibrate(on: const Duration(milliseconds: 200));
        }).catchError((_) {});
      }
    });
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _candidate = null;
      _linked = false;
      _seen.clear();
    });
    await _scanSub?.cancel();
    _scanSub = app.ring.scanResults.listen((r) {
      if (_rejected.contains(r.id)) return;
      _seen.add(r);
    });
    try {
      await app.ring.startScan(timeout: const Duration(seconds: 8));
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    // Pick the strongest signal after a short listen.
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 4), _pick);
  }

  Future<void> _pick() async {
    if (_seen.isEmpty) {
      _deadline = Timer(const Duration(seconds: 5), () {
        if (_seen.isEmpty) {
          if (mounted) setState(() => _scanning = false);
        } else {
          _pick();
        }
      });
      return;
    }
    _seen.sort((a, b) => b.rssi.compareTo(a.rssi));
    final r = _seen.first;
    await app.ring.stopScan();
    if (!mounted) return;
    setState(() {
      _candidate = r;
      _scanning = false;
    });
    await app.ring.connect(r.id);
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _scanSub?.cancel();
    _evSub?.cancel();
    super.dispose();
  }

  String _masked(ScannedRing r) {
    final raw = (r.mac ?? r.id)
        .replaceAll(RegExp('[^0-9A-Fa-f]'), '')
        .toUpperCase();
    final tail = raw.length >= 4 ? raw.substring(raw.length - 4) : raw;
    return 'HE-01-•••$tail';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = _candidate;
    final strong = (c?.rssi ?? -100) > -65;
    return StepScaffold(
      step: 5,
      eyebrow: c == null
          ? (_scanning
                ? context.t('SEARCHING', 'RECHERCHE')
                : context.t('NOTHING FOUND', 'AUCUN BRACELET'))
          : '${context.t('FOUND', 'TROUVÉ')} · ${strong ? context.t('STRONG SIGNAL', 'SIGNAL FORT') : context.t('WEAK SIGNAL', 'SIGNAL FAIBLE')}',
      eyebrowDot: c == null ? null : He.ink,
      title: c == null
          ? (_scanning
                ? context.t(
                    'Looking for your Helium…',
                    'Recherche de votre Helium…',
                  )
                : context.t('No band nearby.', 'Aucun bracelet à proximité.'))
          : context.t('Is this your Helium?', 'Est-ce votre Helium?'),
      subtitle: c == null
          ? (_scanning
                ? null
                : context.t(
                    'Wake the core again and keep it close to your phone.',
                    'Réveillez le cœur et gardez-le près du téléphone.',
                  ))
          : context.t(
              'Your band is pulsing a code now. Does it feel like this: short, long, short?',
              'Votre bracelet émet un code. Le sentez-vous ainsi : court, long, court?',
            ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c != null) ...[
            PillButton(
              _linked
                  ? context.t('Yes, pair it', 'Oui, jumeler')
                  : context.t('Connecting…', 'Connexion…'),
              onTap: _linked
                  ? () async {
                      await state.rememberDevice(c);
                      if (context.mounted) _push(context, const WearStep());
                    }
                  : null,
            ),
            UnderlineLink(
              context.t('That\'s not my band', 'Ce n’est pas mon bracelet'),
              onTap: () async {
                _rejected.add(c.id);
                await app.ring.disconnect();
                _scan();
              },
            ),
          ] else if (!_scanning)
            PillButton(
              context.t('Search again', 'Chercher à nouveau'),
              onTap: _scan,
            ),
        ],
      ),
      children: [
        const SizedBox(height: 40),
        Center(
          child: _scanning && c == null
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: He.ink,
                  ),
                )
              : const _PulseCode(),
        ),
        const SizedBox(height: 50),
        if (c != null) ...[
          const Hairline(),
          RowTile(
            label: 'ALVI Helium',
            value: _masked(c),
            mono: true,
            height: 84,
          ),
          RowTile(
            label: context.t('Firmware', 'Micrologiciel'),
            value: state.versions?.firmware.isNotEmpty == true
                ? state.versions!.firmware
                : '—',
            mono: true,
            height: 84,
          ),
        ],
      ],
    );
  }
}

class _PulseCode extends StatelessWidget {
  const _PulseCode();
  @override
  Widget build(BuildContext context) {
    final shadow = [
      BoxShadow(
        color: He.ink.withValues(alpha: 0.25),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
    Widget dot() => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: He.ink,
        shape: BoxShape.circle,
        boxShadow: shadow,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(),
        const SizedBox(width: 30),
        Container(
          width: 140,
          height: 36,
          decoration: BoxDecoration(
            color: He.ink,
            borderRadius: BorderRadius.circular(18),
            boxShadow: shadow,
          ),
        ),
        const SizedBox(width: 30),
        dot(),
      ],
    );
  }
}

class WearStep extends StatelessWidget {
  const WearStep({super.key, this.editing = false});
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.prefs;
    Widget spot(WearSpot s, String label, String sub) {
      final on = p.wear == s;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            p.wear = s;
            app.save();
          },
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: on ? He.ink : He.hairline,
                      width: on ? 2.4 : 1.4,
                    ),
                  ),
                  child: Center(
                    child: BandGlyph(
                      upperArm: s == WearSpot.upperArm,
                      color: on ? He.ink : He.ink3,
                      size: 70,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    on
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: on ? He.ink : He.ink3,
                  ),
                  const SizedBox(width: 10),
                  Text(label, style: He.sans(22, weight: FontWeight.w300)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: He.sans(15, color: He.ink3),
              ),
            ],
          ),
        ),
      );
    }

    return StepScaffold(
      step: 6,
      eyebrow: context.t('WEAR', 'PORT'),
      title: context.t('Where will you wear it?', 'Où le porterez-vous?'),
      subtitle: context.t(
        'We tune pulse strength to the spot. Move it any time.',
        'Nous ajustons l’intensité selon l’endroit. Changez quand vous voulez.',
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(
              'Snug, one finger of space. The sensor faces your skin.',
              'Ajusté, un doigt d’espace. Le capteur contre la peau.',
            ),
            style: He.sans(14.5, color: He.ink3),
          ),
          const SizedBox(height: 16),
          PillButton(
            editing
                ? context.t('Save', 'Enregistrer')
                : context.t('Continue', 'Continuer'),
            onTap: () => editing
                ? Navigator.pop(context)
                : _push(context, const HapticLanguageStep()),
          ),
        ],
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            spot(
              WearSpot.wrist,
              context.t('Wrist', 'Poignet'),
              context.t(
                'Everyday, knit or sport band',
                'Au quotidien, bracelet tricot ou sport',
              ),
            ),
            const SizedBox(width: 20),
            spot(
              WearSpot.upperArm,
              context.t('Upper arm', 'Haut du bras'),
              context.t(
                'Training, team sports and sleep',
                'Entraînement, sports d’équipe et sommeil',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Hairline(),
        RowTile(
          label: context.t('Band size', 'Taille'),
          height: 76,
          valueWidget: Row(
            children: [
              for (final s in BandSize.values) ...[
                const SizedBox(width: 10),
                PillChoice(
                  s.name.toUpperCase(),
                  compact: true,
                  selected: p.size == s,
                  onTap: () {
                    p.size = s;
                    app.save();
                  },
                ),
              ],
            ],
          ),
        ),
        RowTile(
          label: context.t('Hand', 'Main'),
          height: 76,
          valueWidget: Row(
            children: [
              for (final (h, label) in [
                (Hand.left, context.t('Left', 'Gauche')),
                (Hand.right, context.t('Right', 'Droite')),
              ]) ...[
                const SizedBox(width: 10),
                PillChoice(
                  label,
                  compact: true,
                  selected: p.hand == h,
                  onTap: () {
                    p.hand = h;
                    app.save();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The haptic vocabulary, with play buttons that fire each pattern on the band.
List<(HapticPattern, String, String)> hapticVocabulary(BuildContext c) => [
  (
    HapticPattern.onePulse,
    c.t('One pulse', 'Une pulsation'),
    c.t('You\'re in your zone', 'Vous êtes dans votre zone'),
  ),
  (
    HapticPattern.twoPulses,
    c.t('Two pulses', 'Deux pulsations'),
    c.t('Goal reached', 'Objectif atteint'),
  ),
  (
    HapticPattern.longPulse,
    c.t('One long pulse', 'Une longue pulsation'),
    c.t('Time to move', 'Temps de bouger'),
  ),
  (
    HapticPattern.rising,
    c.t('Rising pulses', 'Pulsations croissantes'),
    c.t('Silent alarm', 'Alarme silencieuse'),
  ),
  (
    HapticPattern.swell,
    c.t('Slow swell', 'Lente montée'),
    c.t('Breathe in, and out', 'Inspirez, expirez'),
  ),
  (
    HapticPattern.shortLong,
    c.t('Short, then long', 'Courte, puis longue'),
    c.t('Battery low', 'Batterie faible'),
  ),
];

class HapticLanguageStep extends StatelessWidget {
  const HapticLanguageStep({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return StepScaffold(
      step: 7,
      eyebrow: context.t('THE HAPTIC LANGUAGE', 'LE LANGAGE HAPTIQUE'),
      title: context.t('It speaks in touch.', 'Il parle par le toucher.'),
      subtitle: context.t(
        'Tap play to feel each pattern on your wrist now.',
        'Touchez lecture pour sentir chaque motif.',
      ),
      footer: PillButton(
        context.t('Finish setup', 'Terminer'),
        onTap: () => _push(context, const PairedScreen()),
      ),
      children: [
        const Hairline(),
        for (final (pattern, title, sub) in hapticVocabulary(context))
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: He.hairline)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: HapticGlyph(pattern),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: He.sans(19)),
                      Text(sub, style: He.sans(15, color: He.ink3)),
                    ],
                  ),
                ),
                PlayButton(onTap: app.ready ? () => app.play(pattern) : null),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: HapticGlyph(null),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: He.sans(17, color: He.ink2, height: 1.45),
                    children: [
                      TextSpan(
                        text: context.t(
                          'And you can talk back: ',
                          'Et vous pouvez répondre : ',
                        ),
                      ),
                      TextSpan(
                        text: context.t('double-tap', 'touchez deux fois'),
                        style: He.sans(
                          17,
                          weight: FontWeight.w700,
                          color: He.ink,
                        ),
                      ),
                      TextSpan(
                        text: context.t(
                          ' the core to start or end a workout. A tick says got it.',
                          ' le cœur pour démarrer ou terminer un entraînement. Un tic confirme.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PlayButton extends StatelessWidget {
  const PlayButton({super.key, this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: He.ink3, width: 1.2),
        ),
        child: const Icon(Icons.play_arrow_rounded, size: 22, color: He.ink),
      ),
    ),
  );
}

class PairedScreen extends StatelessWidget {
  const PairedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nights = app.health.history.where((n) => n.worn).length.clamp(0, 7);
    return Scaffold(
      body: Backdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: He.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              const Center(child: AlviMark(width: 260)),
              const Spacer(flex: 3),
              Eyebrow(
                app.paired
                    ? context.t('PAIRED', 'JUMELÉ')
                    : context.t('SAMPLE MODE', 'MODE EXEMPLE'),
                dot: He.ink,
              ),
              const SizedBox(height: 14),
              Text(
                context.t(
                  'Helium is learning you.',
                  'Helium apprend à vous connaître.',
                ),
                style: He.headline(44),
              ),
              const SizedBox(height: 14),
              Text(
                context.t(
                  'Your baselines form over seven nights. Wear it to sleep tonight.',
                  'Vos références se forment en sept nuits. Portez-le cette nuit.',
                ),
                style: He.body(18),
              ),
              const SizedBox(height: 26),
              Text(
                context.t(
                  'BASELINE · $nights OF 7 NIGHTS',
                  'RÉFÉRENCE · $nights SUR 7 NUITS',
                ),
                style: He.eyebrow(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < nights ? He.ink : He.track,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 26),
              const Hairline(),
              RowTile(
                label: context.t('Wear', 'Port'),
                value:
                    '${app.prefs.wear == WearSpot.wrist ? context.t('WRIST', 'POIGNET') : context.t('UPPER ARM', 'HAUT DU BRAS')} · ${app.prefs.size.name.toUpperCase()}',
                mono: true,
                height: 76,
              ),
              RowTile(
                label: context.t('Battery', 'Batterie'),
                value: app.battery == null ? '—' : '${app.battery!.level}%',
                mono: true,
                height: 76,
              ),
              const Spacer(),
              PillButton(
                context.t('Go to Today', 'Aller à Aujourd’hui'),
                onTap: () async {
                  await app.finishOnboarding();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const Shell()),
                      (_) => false,
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
