import 'package:qring_sdk/qring_sdk.dart';

enum HapticStrength { soft, medium, strong }

/// Helium's haptic vocabulary. The ring's motor has a single amplitude, so
/// each pattern is a sequence of buzz/rest pairs; strength scales buzz length.
enum HapticPattern {
  onePulse([(300, 0)]),
  twoPulses([(220, 220), (220, 0)]),
  longPulse([(1000, 0)]),
  rising([(100, 300), (200, 300), (400, 300), (700, 0)]),
  swell([(1800, 0)]),
  shortLong([(200, 300), (800, 0)]),
  tick([(100, 0)]);

  const HapticPattern(this.segments);

  /// (buzz ms, rest ms) pairs.
  final List<(int, int)> segments;

  Future<void> play(QRing ring, {HapticStrength strength = HapticStrength.medium}) async {
    final scale = switch (strength) {
      HapticStrength.soft => 0.7,
      HapticStrength.medium => 1.0,
      HapticStrength.strong => 1.4,
    };
    for (final (on, off) in segments) {
      final buzz = Duration(milliseconds: (on * scale).round().clamp(100, 12700));
      await ring.vibrate(on: buzz, off: Duration.zero);
      await Future<void>.delayed(buzz + Duration(milliseconds: off));
    }
  }
}
