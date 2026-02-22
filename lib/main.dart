import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'screens/main_navigation.dart';

void main() async {
  // Ensures Flutter is fully initialized before we run any async code
  // Required when you need to do work before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  await NotificationService.instance.initialize();
  await NotificationService.instance.requestPermission();
  await NotificationService.instance.scheduleAllNotifications();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clock In',
      debugShowCheckedModeBanner: false,  // removes the red DEBUG banner
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}
