// lib/app_shell.dart
import 'package:flutter/material.dart';
import 'controllers/health_controller.dart';
import 'pages/home_page.dart';
import 'pages/health_summary_page.dart';
import 'pages/device_control_page.dart';
import 'pages/emergency_contacts_page.dart';
import 'package:health/health.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _warmed = false;

  final _pages = const <Widget>[
    HomePage(),
    HealthSummaryPage(),
    DeviceControlPage(),
    EmergencyContactPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_warmed) return;
      _warmed = true;

      // 필요하면 한 번만 묻기(두 타입을 한 번에)
      try {
        await HealthController.I.requestAllPermsIfNeeded(const [
          HealthDataType.STEPS,
          HealthDataType.SLEEP_SESSION,
        ]);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.monitor_heart_outlined), label: '건강'),
          BottomNavigationBarItem(icon: Icon(Icons.devices_other_outlined), label: '제어'),
          BottomNavigationBarItem(icon: Icon(Icons.emergency_outlined), label: '긴급'),
        ],
      ),
    );
  }
}
