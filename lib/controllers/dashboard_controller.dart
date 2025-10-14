import 'package:flutter/foundation.dart';
import '../data/health_repository.dart';

enum DashboardStatus { idle, loading, ready, error, noPermission }

class DashboardController extends ChangeNotifier {
  final HealthRepository repo;

  DashboardStatus _status = DashboardStatus.idle;
  DashboardStatus get status => _status;

  DashboardSnapshot? _snapshot;
  DashboardSnapshot? get snapshot => _snapshot;

  String? _error;
  String? get error => _error;

  DashboardController(this.repo);

  Future<void> init() async {
    _status = DashboardStatus.loading;
    notifyListeners();
    try {
      final ok = await repo.ensurePermissions();
      if (!ok) {
        _status = DashboardStatus.noPermission;
        notifyListeners();
        return;
      }
      await refresh();
    } catch (e) {
      _status = DashboardStatus.error;
      _error = '초기화 오류: $e';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _status = DashboardStatus.loading;
    notifyListeners();
    try {
      final snap = await repo.readDashboard(now: DateTime.now());
      _snapshot = snap;
      _status = DashboardStatus.ready;
      _error = null;
      notifyListeners();
    } catch (e) {
      _status = DashboardStatus.error;
      _error = '데이터 로딩 오류: $e';
      notifyListeners();
    }
  }

  /// 권한이 거부된 경우 설정화면에서 허용한 뒤 다시 호출
  Future<void> retryAfterPermission() async {
    await refresh();
  }
}
