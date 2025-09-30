// lib/base_health_page.dart
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'health_controller.dart';

abstract class HealthStatefulPage extends StatefulWidget {
  const HealthStatefulPage({super.key});
}

abstract class HealthState<T extends HealthStatefulPage> extends State<T> {
  bool authorized = false;
  String? errorMsg;

  /// 각 페이지에서 필요한 타입만 정의
  List<HealthDataType> get types;

  Health get health => HealthController.I.health;

  @override
  void initState() {
    super.initState();
    _initHealthFlow();
  }

  Future<void> _initHealthFlow() async {
    try {
      await HealthController.I.ensureConfigured();

      final has = await HealthController.I.hasPermsFor(types);
      if (!has) {
        final ok = await HealthController.I.requestPermsFor(types);
        authorized = ok;
      } else {
        authorized = true;
      }
    } catch (e) {
      errorMsg = '권한 초기화 오류: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }
}

