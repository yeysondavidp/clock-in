import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../database/database_helper.dart';

class NotificationService {
  // Singleton pattern — same reason as DatabaseHelper,
  // we only want one instance managing notifications
  static final NotificationService instance = NotificationService._init();
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  NotificationService._init();

  // Notification IDs — fixed constants so we can cancel/replace them
  static const int checkinNotificationId  = 1;
  static const int checkoutNotificationId = 2;

  // ─── INITIALIZATION ─────────────────────────────────────

  Future<void> initialize() async {
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);
  }

  // Request permission — Android 13+ requires explicit permission
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  // ─── SCHEDULE NOTIFICATIONS ─────────────────────────────

  // Called on app start and every time settings change
  Future<void> scheduleAllNotifications() async {
    final db = DatabaseHelper.instance;

    final notificationsEnabled =
        await db.getSetting('notifications_enabled') ?? 'true';

    // If user disabled notifications, cancel everything and stop
    if (notificationsEnabled == 'false') {
      await cancelAllNotifications();
      return;
    }

    final checkinTime  = await db.getSetting('checkin_notification_time')  ?? '08:00';
    final checkoutTime = await db.getSetting('checkout_notification_time') ?? '17:00';

    await _scheduleWeeklyNotification(
      id:      checkinNotificationId,
      title:   'Clock In',
      body:    'Time to clock in to work!',
      time:    checkinTime,
    );

    await _scheduleWeeklyNotification(
      id:      checkoutNotificationId,
      title:   'Clock Out',
      body:    'Time to clock out!',
      time:    checkoutTime,
    );
  }

  // Schedules a notification that repeats Monday to Friday
  Future<void> _scheduleWeeklyNotification({
    required int id,
    required String title,
    required String body,
    required String time,
  }) async {
    // Cancel existing notification with this ID before rescheduling
    await _plugin.cancel(id);

    final parts  = time.split(':');
    final hour   = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final now = tz.TZDateTime.now(tz.local);

    // Schedule one notification per weekday (Monday=1 to Friday=5)
    // Flutter local notifications doesn't support "weekdays only" natively
    // so we schedule 5 separate notifications, one per day
    for (int weekday = DateTime.monday; weekday <= DateTime.friday; weekday++) {
      final scheduledDate = _nextWeekday(now, weekday, hour, minute);

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'clock_in_channel_$weekday',   // channel ID
          'Clock In Reminders',          // channel name visible to user in settings
          channelDescription: 'Daily work reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

      // ID offset by weekday so each day has a unique ID
      // checkin monday = 11, tuesday = 12 ... friday = 15
      // checkout monday = 21, tuesday = 22 ... friday = 25
      await _plugin.zonedSchedule(
        id * 10 + weekday,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  // Finds the next occurrence of a given weekday at a given time
  // Example: next Monday at 08:00
  tz.TZDateTime _nextWeekday(
      tz.TZDateTime from, int weekday, int hour, int minute) {
    // Start with today at the target time
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      from.year,
      from.month,
      from.day,
      hour,
      minute,
    );

    // Advance day by day until we land on the right weekday
    // and the time hasn't passed yet today
    while (scheduled.weekday != weekday || scheduled.isBefore(from)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  // ─── HOLIDAY CHECK ──────────────────────────────────────

  // Called when a notification fires — checks if today is a holiday
  // If it is, the app ignores the notification action
  // (We can't cancel a notification for a specific date easily,
  // so we check at the moment the user taps it)
  Future<bool> isTodayHoliday() async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return await DatabaseHelper.instance.isHoliday(dateStr);
  }

  // ─── CANCEL ─────────────────────────────────────────────

  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }
}