// lib/data/iot/device_control_controller.dart

import 'dart:async';
import 'package:flutter/material.dart'; // Color 사용을 위해 추가
import 'package:shared_preferences/shared_preferences.dart';
import 'iot_repository.dart';
import 'models.dart';

enum IotStatus { idle, loading, ready, error }

class DeviceControlController extends ChangeNotifier {
  final IotRepository repo;

  IotStatus status = IotStatus.idle;
  IotSnapshot snapshot = IotSnapshot.initial();

  int _airconSeq = 0;
  Timer? _tempDebounceTimer;

  DeviceControlController(this.repo);

  Future<void> init() async {
    status = IotStatus.loading;
    notifyListeners();
    try {
      snapshot = await repo.load();

      // 에어컨이 꺼져있다면 마지막 상태 복원, 켜져있다면 현재 상태 저장
      if (!snapshot.aircon.isOn) {
        await _restoreLastSettings();
      } else {
        await _saveCurrentSettings();
      }

      status = IotStatus.ready;
    } catch (_) {
      status = IotStatus.error;
    }
    notifyListeners();
  }

  // ================= UI 헬퍼 (배경색) =================

  /// 현재 에어컨 모드에 알맞는 배경 색상을 반환합니다.
  /// UI 쪽에서 controller.uiColor 로 접근해서 사용하세요.
  Color get uiColor {
    if (!snapshot.aircon.isOn) {
      return Colors.white; // 꺼짐 (기본 흰색)
    }
    switch (snapshot.aircon.mode) {
      case AcMode.heat:
        return const Color(0xFFFFF3E0); // 난방: 연한 주황
      case AcMode.cool:
        return const Color(0xFFE3F2FD); // 냉방: 연한 파랑
      case AcMode.dry:
        return const Color(0xFFF3E5F5); // 제습: 연한 보라
      case AcMode.fan:
        return const Color(0xFFE8F5E9); // 송풍: 연한 초록
      case AcMode.auto:
        return const Color(0xFFE0F2F1); // 자동: 연한 청록
    }
  }

  Color get activeColor {
    if (!snapshot.aircon.isOn) return Colors.grey;
    switch (snapshot.aircon.mode) {
      case AcMode.heat: return Colors.orange;
      case AcMode.cool: return Colors.blue;
      case AcMode.dry: return Colors.purple;
      case AcMode.fan: return Colors.green;
      case AcMode.auto: return Colors.teal;
    }
  }

  // ================= 에어컨 제어 로직 =================

  Future<void> toggleAc() async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(isOn: !prev.isOn);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();

    _saveCurrentSettings();

    try {
      await repo.setAcPower(optimistic.isOn);
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: prev);
        notifyListeners();
      }
    }
  }

  Future<void> acTempDelta(int d) async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final newTemp = (prev.temperature + d).clamp(16, 30) as int;
    final optimistic = prev.copyWith(temperature: newTemp);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();

    _saveCurrentSettings();

    if (_tempDebounceTimer?.isActive ?? false) _tempDebounceTimer!.cancel();
    _tempDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await repo.setAcTemp(newTemp);
      } catch (_) {
        if (seq == _airconSeq) {
          snapshot = snapshot.copyWith(aircon: prev);
          notifyListeners();
        }
      }
    });
  }

  Future<void> setTargetTemperature(double val) async {
    final int target = val.toInt().clamp(16, 30);
    if (target == snapshot.aircon.temperature) return;

    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(temperature: target);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();

    _saveCurrentSettings();

    if (_tempDebounceTimer?.isActive ?? false) _tempDebounceTimer!.cancel();
    _tempDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await repo.setAcTemp(target);
      } catch (_) {
        if (seq == _airconSeq) {
          snapshot = snapshot.copyWith(aircon: prev);
          notifyListeners();
        }
      }
    });
  }

  // ✅ [수정됨] 모드 변경 시 해당 모드의 마지막 온도를 불러옴
  Future<void> setAcMode(AcMode newMode) async {
    if (snapshot.aircon.mode == newMode) return;

    final seq = ++_airconSeq;
    final prev = snapshot.aircon;

    // 1. 새 모드에 저장된 마지막 온도를 불러오기 (없으면 기본값)
    final savedTemp = await _getSavedTempForMode(newMode);

    // 2. 모드와 온도를 동시에 업데이트
    final optimistic = prev.copyWith(
      mode: newMode,
      temperature: savedTemp,
    );

    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();

    // 3. 변경된 상태 즉시 저장
    _saveCurrentSettings();

    try {
      await repo.setAcMode(newMode);
      if (prev.temperature != savedTemp) {
        await repo.setAcTemp(savedTemp);
      }
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: prev);
        notifyListeners();
      }
    }
  }

  Future<void> setAcTimer(int h) async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(timerHours: h);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();
    try { await repo.setAcTimer(h); } catch (_) {
      if (seq == _airconSeq) { snapshot = snapshot.copyWith(aircon: prev); notifyListeners(); }
    }
  }

  Future<void> setAcFanSpeed(AcFanSpeed speed) async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(fanSpeed: speed);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();
    _saveCurrentSettings();
    try { await repo.setAcFanSpeed(speed); } catch (_) { /* 롤백 */ }
  }

  // (기타 메서드)
  Future<void> toggleAcSwing() async {}
  Future<void> toggleHrv() async {}
  Future<void> setBlinds(BlindsStatus st) async {}
  Future<void> toggleLight(String room) async {}
  Future<void> setBrightness(String room, BrightnessLevel b) async {}


  // =========================================================
  // ✅ [업그레이드] 모드별 온도 저장 및 복원 로직
  // =========================================================

  static const _keyLastMode = 'ac_last_mode_idx';
  static const _keyLastFan = 'ac_last_fan_idx';

  // 모드별 온도 키 생성 헬퍼
  String _tempKey(AcMode m) => 'ac_temp_${m.name}';

  int _defaultTempFor(AcMode m) {
    switch (m) {
      case AcMode.heat: return 26; // 난방은 따뜻하게
      case AcMode.cool: return 24; // 냉방은 시원하게
      case AcMode.dry: return 24;
      default: return 24;
    }
  }

  Future<int> _getSavedTempForMode(AcMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_tempKey(mode)) ?? _defaultTempFor(mode);
  }

  Future<void> _saveCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ac = snapshot.aircon;
    await prefs.setInt(_keyLastMode, ac.mode.index);
    await prefs.setInt(_keyLastFan, ac.fanSpeed.index);
    await prefs.setInt(_tempKey(ac.mode), ac.temperature);
  }

  Future<void> _restoreLastSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedModeIdx = prefs.getInt(_keyLastMode);
    final savedFanIdx = prefs.getInt(_keyLastFan);

    AirconState newAc = snapshot.aircon;

    if (savedModeIdx != null && savedModeIdx < AcMode.values.length) {
      newAc = newAc.copyWith(mode: AcMode.values[savedModeIdx]);
    }
    if (savedFanIdx != null && savedFanIdx < AcFanSpeed.values.length) {
      newAc = newAc.copyWith(fanSpeed: AcFanSpeed.values[savedFanIdx]);
    }

    final savedTemp = prefs.getInt(_tempKey(newAc.mode));
    if (savedTemp != null) {
      newAc = newAc.copyWith(temperature: savedTemp);
    } else {
      newAc = newAc.copyWith(temperature: _defaultTempFor(newAc.mode));
    }

    snapshot = snapshot.copyWith(aircon: newAc);
  }
}