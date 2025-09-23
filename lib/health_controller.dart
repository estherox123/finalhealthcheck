import 'package:health/health.dart';                       // Health, HealthDataType, ...
import 'package:permission_handler/permission_handler.dart';// Permission

class HealthController {
  HealthController._();
  static final HealthController I = HealthController._();

  final Health health = Health();
  bool _configured = false;

  Future<void> ensureConfigured() async {
    if (_configured) return;
    await health.configure();
    _configured = true;
  }

  // ✅ 페이지별 타입으로 권한 확인
  Future<bool> hasPermsFor(List<HealthDataType> types) async {
    final reads = List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);
    return await health.hasPermissions(types, permissions: reads) ?? false;
  }

  // ✅ 페이지별 타입으로 권한 요청
  Future<bool> requestPermsFor(List<HealthDataType> types) async {
    await Permission.activityRecognition.request();

    // Health Connect 설치 유도 (미지원 단말은 예외가 발생할 수 있으므로 무시)
    try {
      await health.installHealthConnect();
    } catch (_) {}

    final available = await health.isHealthConnectAvailable();
    if (!available) {
      return false;
    }

    final reads = List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);

    if (await hasPermsFor(types)) {
      return true;
    }

    final ok = await health.requestAuthorization(types, permissions: reads);
    final after = await hasPermsFor(types);
    return ok && after;
  }
}
