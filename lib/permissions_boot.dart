import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health/health.dart';

/// 첫 실행 때 한 번만 띄워서 Health Connect + 런타임 권한을 모두 받아오는 페이지
class PermissionsBootPage extends StatefulWidget {
  const PermissionsBootPage({super.key});
  @override
  State<PermissionsBootPage> createState() => _PermissionsBootPageState();
}

class _PermissionsBootPageState extends State<PermissionsBootPage> {
  final Health _health = Health();
  String _status = '초기화 중…';
  bool _busy = true;
  String? _error;

  // 한 번에 요청할 타입들(지원 안 되는 항목은 자동으로 무시됨)
  static const _types = <HealthDataType>[
    // 활동/수면
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_IN_BED,
    // 바이탈
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
  ];
  static final _reads = List<HealthDataAccess>.filled(_types.length, HealthDataAccess.READ);

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      setState(() { _busy = true; _status = '런타임 권한 확인…'; });


      // 2) Health permission launcher 등록
      setState(() { _status = 'Health Connect 초기화…'; });
      await _health.configure();

      // 3) Health Connect 읽기 권한 일괄 요청
      setState(() { _status = 'Health Connect 권한 요청…'; });
      final already = await _health.hasPermissions(_types, permissions: _reads) ?? false;
      final ok = already ? true : await _health.requestAuthorization(_types, permissions: _reads);
      if (!ok) throw 'Health Connect 권한 일부/전체 거부됨';

      // 4) 온보딩 완료 플래그 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hc_boot_done', true);

      if (!mounted) return;
      // 5) 홈으로 리셋 네비게이션 (모든 페이지가 깨끗이 다시 빌드되도록)
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      setState(() { _error = '$e'; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('권한 설정')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _busy
              ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
            ],
          )
              : (_error != null)
              ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 36),
              const SizedBox(height: 12),
              Text('권한 설정 실패\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _run,
                child: const Text('다시 시도'),
              ),
            ],
          )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
