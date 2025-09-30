import 'package:health/health.dart';

/// 앱 시작 시 한 번 호출해서 Health Connect에 앱 등록을 트리거
Future<void> bootHealthConnect() async {
  final health = Health();
  try {
    try { await health.installHealthConnect(); } catch (_) {}
    await health.configure();

    // 1차: 수면 세션만 (등록 성공률↑)
    const s = [HealthDataType.SLEEP_SESSION];
    bool ok = await health.requestAuthorization(s);

    // 2차: 걸음도 요청
    const t = [HealthDataType.STEPS];
    if (!ok) {
      ok = await health.requestAuthorization(t);
    } else {
      await health.requestAuthorization(t);
    }
  } catch (_) {
    // 로그만 무시
  }
}
