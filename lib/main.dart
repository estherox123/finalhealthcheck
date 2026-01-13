// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ 화면 회전 고정용 패키지
import 'package:intl/date_symbol_data_local.dart';
import 'app_shell.dart';
import 'services/reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 모바일 앱은 '세로 모드'로 고정 (미러랑 꼬이지 않게)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await initializeDateFormatting('ko_KR', null); // 언어 설정 명시

  // 기존 알림 서비스 유지
  await ReminderService.instance.init();
  ReminderService.instance.checkScheduledReminders();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wellness Mobile',
      debugShowCheckedModeBanner: false,
      // 모바일용 테마 (밝은 배경)
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const AppShell(), // ✅ 기존 탭 메뉴 실행
    );
  }
}