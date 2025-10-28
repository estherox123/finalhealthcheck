// lib/main.dart
import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'services/reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderService.instance.init();
  
  // Check for due reminders when app starts
  ReminderService.instance.checkScheduledReminders();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wellness Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const AppShell(),
    );
  }
}
