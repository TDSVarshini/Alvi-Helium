import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';

/// "Phone sound backup" for the silent alarm: a sounding notification a few
/// minutes after the wake window closes, on each selected weekday.
class AlarmBackup {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _baseId = 4100; // ids 4101..4107, one per weekday
  static const grace = Duration(minutes: 5);

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('alarm backup init: $e');
    }
  }

  static Future<bool> _askPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  /// Reschedules (or clears) the backup notifications for [a].
  static Future<void> apply(AlarmWindow a, {required String title, required String body}) async {
    await init();
    if (!_ready) return;
    for (var d = 1; d <= 7; d++) {
      await _plugin.cancel(id: _baseId + d);
    }
    if (!a.enabled || !a.phoneBackup || a.days.isEmpty) return;
    if (!await _askPermission()) return;
    final fireAt = a.latest + grace.inMinutes;
    for (final day in a.days) {
      await _plugin.zonedSchedule(
        id: _baseId + day,
        title: title,
        body: body,
        scheduledDate: _next(day, fireAt ~/ 60, fireAt % 60),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'helium_alarm_backup',
            'Alarm backup',
            channelDescription: 'Sounds if you sleep through the silent alarm',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
          ),
          iOS: DarwinNotificationDetails(presentSound: true, interruptionLevel: InterruptionLevel.timeSensitive),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  static tz.TZDateTime _next(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (t.weekday != weekday || !t.isAfter(now)) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }
}
