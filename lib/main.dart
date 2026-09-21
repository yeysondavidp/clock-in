import 'package:clock_in/services/work_notification_service.dart';
import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'screens/main_navigation.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw the UI first; service setup must never block the first frame
  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) => _initServices());
}

// Each step runs independently with a timeout so a hung platform call
// (permission dialog, settings intent) can't stall the rest.
Future<void> _initServices() async {
  await _runStep('WorkManager init',
      () => WorkNotificationService.instance.initialize());
  await _runStep('Notifications init',
      () => NotificationService.instance.initialize());
  await _runStep('WorkManager scheduling',
      () => WorkNotificationService.instance.scheduleAllNotifications());
  // User-facing prompts go last and may wait on the user
  await _runStep('Notification permission',
      () => NotificationService.instance.requestPermission(),
      timeout: const Duration(minutes: 1));
  await _runStep('Battery optimization exemption',
      () => WorkNotificationService.instance.requestBatteryOptimizationExemption());
}

Future<void> _runStep(String name, Future<void> Function() step,
    {Duration timeout = const Duration(seconds: 10)}) async {
  try {
    await step().timeout(timeout);
  } catch (e) {
    debugPrint('$name failed: $e');
  }
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