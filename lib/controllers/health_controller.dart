import 'package:health/health.dart';

class HealthController {
  HealthController._();
  static final HealthController I = HealthController._();

  final Health _health = Health();
  bool _configured = false;

  Health get health => _health;

  /// configure()는 1회만
  Future<void> ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// 주어진 타입들에 대해 READ 권한이 없으면 한 번 요청하고 결과 반환
  Future<bool> requestAllPermsIfNeeded(List<HealthDataType> types) async {
    if (types.isEmpty) return true;
    final reads = types.map((_) => HealthDataAccess.READ).toList();
    final has = await _health.hasPermissions(types, permissions: reads) ?? false;
    if (has) return true;
    return await _health.requestAuthorization(types, permissions: reads);
  }
}
