import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../data/daily_verses.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'daily_verse';
  static const _lockChannelId = 'lock_screen_verse';
  static const _lockNotifId = 9999;
  static const _scheduledDays = 60;

  static Future<void> initialize() async {
    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> scheduleDaily(int hour, int minute) async {
    await _plugin.cancelAll();

    final now = tz.TZDateTime.now(tz.local);
    var firstFire = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute,
    );
    if (firstFire.isBefore(now)) {
      firstFire = firstFire.add(const Duration(days: 1));
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Daily Verse',
        channelDescription: 'Daily scripture verse reminder',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );

    for (int i = 0; i < _scheduledDays; i++) {
      final fireTime = firstFire.add(Duration(days: i));
      final date = DateTime(fireTime.year, fireTime.month, fireTime.day);
      final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
      final verse = kDailyVerses[dayOfYear % kDailyVerses.length];

      await _plugin.zonedSchedule(
        i,
        'Your daily verse',
        '${verse['ref']} — ${verse['text']}',
        fireTime,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Posts (or refreshes) an ongoing, silent, public-visibility notification
  /// showing today's verse. Appears on the lock screen without unlocking the
  /// device. Call after scheduleDaily() since that cancels all notifications.
  static Future<void> showLockScreen() async {
    final verse = getDailyVerse();
    final text = verse['text'] ?? '';
    final ref = verse['ref'] ?? '';

    await _plugin.show(
      _lockNotifId,
      ref,
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _lockChannelId,
          'Lock Screen Verse',
          channelDescription: 'Today\'s verse on your lock screen all day',
          importance: Importance.low,
          priority: Priority.low,
          visibility: NotificationVisibility.public,
          ongoing: true,
          playSound: false,
          enableVibration: false,
          styleInformation: BigTextStyleInformation(text),
        ),
      ),
    );
  }

  static Future<void> cancelLockScreen() async {
    await _plugin.cancel(_lockNotifId);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Parses a time string like '8:00 AM' into hour/minute integers.
  static (int hour, int minute) parseTimeString(String timeStr) {
    final parts = timeStr.trim().split(' ');
    final timeParts = parts[0].split(':');
    int hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    if (parts.length > 1 && parts[1] == 'PM' && hour != 12) hour += 12;
    if (parts.length > 1 && parts[1] == 'AM' && hour == 12) hour = 0;
    return (hour, minute);
  }
}
