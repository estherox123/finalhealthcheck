// lib/widgets/permission_banner.dart
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import '../data/health_data_service.dart';

class PermissionBanner extends StatefulWidget {
  final List<HealthDataType> types;
  final VoidCallback? onGranted; // 권한 허용 후 콜백(데이터 리로드 등)
  const PermissionBanner({
    super.key,
    this.types = kRecommendedTypes,
    this.onGranted,
  });

  @override
  State<PermissionBanner> createState() => _PermissionBannerState();
}

class _PermissionBannerState extends State<PermissionBanner>
    with WidgetsBindingObserver {
  final _svc = HealthDataService();
  bool _checking = true;
  bool _granted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check(); // 설정에서 돌아오면 재확인
    }
  }

  Future<void> _check() async {
    setState(() { _checking = true; });
    try {
      final health = Health();
      final perms = List<HealthDataAccess>.filled(
          widget.types.length, HealthDataAccess.READ);
      final ok = await health.hasPermissions(widget.types, permissions: perms) ?? false;
      if (!mounted) return;
      setState(() {
        _granted = ok;
        _checking = false;
      });
      if (ok && widget.onGranted != null) widget.onGranted!();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _granted = false;
        _checking = false;
      });
    }
  }

  Future<void> _request() async {
    setState(() => _checking = true);
    final ok = await _svc.requestOrOpenSettings(widget.types);
    if (!mounted) return;
    setState(() {
      _granted = ok;
      _checking = false;
    });
    if (ok && widget.onGranted != null) widget.onGranted!();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _granted) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_open_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Health Connect 권한이 필요합니다. 권한을 허용하면 걸음/수면 등의 정보를 볼 수 있어요.',
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _request,
            child: const Text('권한 설정하기'),
          ),
        ],
      ),
    );
  }
}
