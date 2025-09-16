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
    await Permission.activityRecognition.request(); // 보완용(권장)
    final reads = List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);

    final had = await hasPermsFor(types);
    if (had) return true;

    final ok = await health.requestAuthorization(types, permissions: reads);
    final after = await hasPermsFor(types); // 요청 직후 재확인
    return ok && after;
  }
}
