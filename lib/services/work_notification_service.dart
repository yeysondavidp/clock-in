import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import '../database/database_helper.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';


@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      switch (taskName) {
        case 'checkin_notification':
          await _showNotification(
            id: 1,
            title: 'Clock In',
            body: 'Time to clock in to work!',
          );
          // Reschedule for next working day
          await _rescheduleForNextWorkingDay(
            taskName: 'checkin_notification',
            time: await _getSettingValue('checkin_notification_time', '08:00'),
          );
          break;
        case 'checkout_notification':
          await _showNotification(
            id: 2,
            title: 'Clock Out',
            body: 'Time to clock out!',
          );
          await _rescheduleForNextWorkingDay(
            taskName: 'checkout_notification',
            time: await _getSettingValue('checkout_notification_time', '17:00'),
          );
          break;
      }
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

Future<void> _showNotification({
  required int id,
  required String title,
  required String body,
}) async {
  try {
    print('_showNotification called: $title');

    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      print('Skipping: weekend');
      return;
    }

    final db = DatabaseHelper.instance;
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final isHoliday = await db.isHoliday(dateStr);
    if (isHoliday) {
      print('Skipping: holiday');
      return;
    }

    print('Initializing plugin...');
    final plugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
    );
    print('Plugin initialized');

    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'clock_in_main_channel',
          'Clock In Reminders',
          channelDescription: 'Daily work reminders',
          importance: Importance.max,
          priority: Priority.max,
        ),
      ),
    );
    print('Notification shown successfully');

  } catch (e, stackTrace) {
    print('_showNotification ERROR: $e');
    print('StackTrace: $stackTrace');
  }
}

Future<void> _rescheduleForNextWorkingDay({
  required String taskName,
  required String time,
}) async {
  final parts = time.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);

  // Find next working day (skip weekends)
  var target = DateTime.now().add(const Duration(days: 1));
  target = DateTime(target.year, target.month, target.day, hour, minute);

  while (target.weekday == DateTime.saturday ||
      target.weekday == DateTime.sunday) {
    target = target.add(const Duration(days: 1));
  }

  // Check if next day is a holiday
  final db = DatabaseHelper.instance;
  while (true) {
    final dateStr =
        '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
    final isHoliday = await db.isHoliday(dateStr);
    if (!isHoliday) break;
    target = target.add(const Duration(days: 1));
    // Skip weekends after holiday
    while (target.weekday == DateTime.saturday ||
        target.weekday == DateTime.sunday) {
      target = target.add(const Duration(days: 1));
    }
  }

  final delay = target.difference(DateTime.now());

  await Workmanager().registerOneOffTask(
    taskName,
    taskName,
    initialDelay: delay,
    constraints: Constraints(networkType: NetworkType.notRequired),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    inputData: {
      'taskName': taskName,
    },
  );
}



Future<String> _getSettingValue(String key, String defaultValue) async {
  try {
    final db = DatabaseHelper.instance;
    return await db.getSetting(key) ?? defaultValue;
  } catch (e) {
    return defaultValue;
  }
}

class WorkNotificationService {
  static final WorkNotificationService instance =
  WorkNotificationService._init();
  WorkNotificationService._init();

  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  Future<void> requestBatteryOptimizationExemption() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 23) {
        final intent = AndroidIntent(
          action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          data: 'package:com.polartico.clock_in',
        );
        await intent.launch();
      }
    }
  }

  Future<void> scheduleAllNotifications() async {
    final db = DatabaseHelper.instance;

    final notificationsEnabled =
        await db.getSetting('notifications_enabled') ?? 'true';
    if (notificationsEnabled == 'false') {
      await cancelAllNotifications();
      return;
    }

    final checkinTime =
        await db.getSetting('checkin_notification_time') ?? '08:00';
    final checkoutTime =
        await db.getSetting('checkout_notification_time') ?? '16:00';

    await _scheduleDaily('checkin_notification', checkinTime);
    await _scheduleDaily('checkout_notification', checkoutTime);
  }

  Future<void> _scheduleDaily(String taskName, String time) async {
    await Workmanager().cancelByUniqueName(taskName);

    final delay = _delayUntilNextTime(time);

    await Workmanager().registerOneOffTask(
      taskName,
      taskName,
      initialDelay: delay,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      inputData: {
        'taskName': taskName,
      },
    );
  }

  Duration _delayUntilNextTime(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);

    // If time already passed today, schedule for tomorrow
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }

    return target.difference(now);
  }

  Future<void> cancelAllNotifications() async {
    await Workmanager().cancelAll();
  }


}