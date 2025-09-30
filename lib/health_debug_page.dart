import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io' show Platform;

class HealthDebugPage extends StatefulWidget {
  const HealthDebugPage({super.key});
  @override
  State<HealthDebugPage> createState() => _HealthDebugPageState();
}

class _HealthDebugPageState extends State<HealthDebugPage> {
  final Health _health = Health();

  String pkg = '';
  String log = '';
  bool? available;
  bool stepsHas = false;
  bool sleepHas = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      pkg = info.packageName;
    } catch (_) {}
    try {
      available = await _health.isHealthConnectAvailable();
    } catch (e) {
      available = false;
      log = 'isHealthConnectAvailable error: $e';
    }
    setState(() {});
  }

  Future<void> _checkPerms() async {
    try {
      stepsHas = await _health.hasPermissions(
        const [HealthDataType.STEPS],
        permissions: const [HealthDataAccess.READ],
      ) ?? false;
      sleepHas = await _health.hasPermissions(
        const [HealthDataType.SLEEP_SESSION],
        permissions: const [HealthDataAccess.READ],
      ) ?? false;
      setState(() {});
    } catch (e) {
      setState(() => log = 'hasPermissions error: $e');
    }
  }

  Future<void> _request(List<HealthDataType> types) async {
    try {
      try { await _health.installHealthConnect(); } catch (_) {}
      await _health.configure();

      bool ok = await _health.requestAuthorization(types);                // 1차
      if (!ok) {                                                         // 2차(호환)
        final reads = List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);
        ok = await _health.requestAuthorization(types, permissions: reads);
      }
      setState(() => log = 'requestAuthorization(${types.map((e)=>e.name).toList()}): $ok');
      await _checkPerms();
    } catch (e) {
      setState(() => log = 'request error: $e');
    }
  }

  Future<void> _openHealthConnectSettings() async {
    if (!Platform.isAndroid) return;
    // Android 14+ 내장 HC 설정 열기(가능한 기기에서 동작), 실패 시 HC 앱 정보로 폴백
    try {
      final intent = const AndroidIntent(action: 'android.settings.HEALTH_CONNECT_SETTINGS');
      await intent.launch();
    } catch (_) {
      const hcPkg = 'com.google.android.apps.healthdata';
      final intent = const AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$hcPkg',
      );
      await intent.launch();
    }
  }

  Future<void> _openThisAppInfo() async {
    if (!Platform.isAndroid || pkg.isEmpty) return;
    final intent = AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$pkg',
    );
    await intent.launch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Connect 디버그')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('런타임 패키지명: ${pkg.isEmpty ? "(확인중)" : pkg}'),
            const SizedBox(height: 6),
            Text('Health Connect 가용: ${available == null ? "(확인중)" : (available! ? "가능" : "불가")}'),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('STEPS 권한: ${stepsHas ? "있음" : "없음"}')),
                const SizedBox(width: 8),
                Expanded(child: Text('SLEEP_SESSION 권한: ${sleepHas ? "있음" : "없음"}')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(onPressed: _checkPerms, child: const Text('권한 상태 확인')),
              FilledButton(onPressed: () => _request(const [HealthDataType.SLEEP_SESSION]), child: const Text('수면 세션 요청')),
              FilledButton(onPressed: () => _request(const [HealthDataType.STEPS]), child: const Text('걸음 요청')),
              FilledButton(onPressed: () => _request(const [HealthDataType.SLEEP_SESSION, HealthDataType.STEPS]), child: const Text('수면+걸음 동시 요청')),
              OutlinedButton(onPressed: _openHealthConnectSettings, child: const Text('Health Connect 설정 열기')),
              OutlinedButton(onPressed: _openThisAppInfo, child: const Text('내 앱 정보 열기')),
            ]),
            const SizedBox(height: 10),
            const Text('로그:'),
            Text(log, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            const Text('※ 팁: 권한 요청이 성공해야 Health Connect “앱 권한” 목록에 표시됩니다.'),
          ],
        ),
      ),
    );
  }
}
