//base_health_page.dart
///HealthController로 권한 초기화/요청 처리. 각 페이지에서 필요한 HealthDataType 목록만 지정.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import '../controllers/health_controller.dart';

abstract class HealthStatefulPage extends StatefulWidget {
  const HealthStatefulPage({super.key});
}

abstract class HealthState<T extends HealthStatefulPage> extends State<T> {
  bool authorized = false;
  String? errorMsg;

  final Completer<bool> _authReady = Completer<bool>();
  Future<bool> get authReady => _authReady.future;

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
      // hasPermsFor / requestPermsFor 대신 단일 메서드로 처리
      authorized = await HealthController.I.requestAllPermsIfNeeded(types);
    } catch (e) {
      errorMsg = '권한 초기화 오류: $e';
    } finally {
      if (!_authReady.isCompleted) _authReady.complete(authorized);
      if (mounted) setState(() {});
    }
  }
}
