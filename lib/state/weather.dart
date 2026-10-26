import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class Weather {
  Weather(this.tempC, this.code, this.precip);
  final double tempC;
  final int code; // WMO weather code
  final double precip;

  bool get clear => code <= 1;
  bool get rain => (code >= 51 && code <= 67) || (code >= 80 && code <= 82);
  bool get snow => (code >= 71 && code <= 77) || code == 85 || code == 86;
}

/// Current conditions from Open-Meteo (no key). Uses the last known position
/// only, so it never prompts for location by itself.
Future<Weather?> fetchWeather() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getLastKnownPosition();
    if (pos == null) return null;
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': pos.latitude.toStringAsFixed(2),
      'longitude': pos.longitude.toStringAsFixed(2),
      'current': 'temperature_2m,weather_code,precipitation',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    final c = (jsonDecode(r.body) as Map)['current'] as Map;
    return Weather((c['temperature_2m'] as num).toDouble(), (c['weather_code'] as num).toInt(),
        (c['precipitation'] as num?)?.toDouble() ?? 0);
  } catch (_) {
    return null;
  }
}
