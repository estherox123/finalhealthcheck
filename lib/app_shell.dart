// lib/app_shell.dart
import 'package:flutter/material.dart';
import 'home_page.dart';
import 'health_summary_page.dart';
import 'device_control_page.dart';
import 'emergency_contacts_page.dart';
import 'health_controller.dart';
import 'package:health/health.dart'; // ← 필요

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _warmed = false;

  static final _pages = <Widget>[
    const HomePage(),
    const HealthSummaryPage(),
    const DeviceControlPage(),
    const EmergencyContactPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Activity가 준비된 후(첫 프레임) 1회만 권한 트리거
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_warmed) return;
      _warmed = true;
      try {
        await HealthController.I.ensureConfigured();
        await HealthController.I.requestPermsFor(const [HealthDataType.SLEEP_SESSION]);
        await HealthController.I.requestPermsFor(const [HealthDataType.STEPS]);
      } catch (_) {
        // 실패해도 흐름은 계속
      }
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
