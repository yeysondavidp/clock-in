import 'package:clock_in/services/work_notification_service.dart';
import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'screens/main_navigation.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.initialize();
  await NotificationService.instance.requestPermission();
  await WorkNotificationService.instance.initialize();
  await WorkNotificationService.instance.requestBatteryOptimizationExemption();

  try {
    await WorkNotificationService.instance.scheduleAllNotifications();
  } catch (e) {
    debugPrint('WorkManager scheduling failed: $e');
  }

  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clock In',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}