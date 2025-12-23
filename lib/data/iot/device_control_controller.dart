// lib/data/iot/device_control_controller.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'iot_repository.dart';
import 'models.dart';

enum IotStatus { idle, loading, ready, error }

class DeviceControlController extends ChangeNotifier {
  final IotRepository repo;

  IotStatus status = IotStatus.idle;
  IotSnapshot snapshot = IotSnapshot.initial();

  int _airconSeq = 0;
  int _hrvSeq = 0;
  int _blindsSeq = 0;
  int _lightsSeq = 0;

  Timer? _tempDebounceTimer;

  DeviceControlController(this.repo);

  Future<void> init() async {
    status = IotStatus.loading;
    notifyListeners();
    try {
      // 1. 실제 데이터 가져오기
      snapshot = await repo.load();

      // 2. ✅ 꺼져있다면, 마지막으로 기억하는 설정(난방 등)을 덮어씌움
      if (!snapshot.aircon.isOn) {
        await _restoreLastSettings();
      } else {
        // 켜져있다면, 현재 상태를 저장해둠 (다음번을 위해)
        await _saveCurrentSettings();
      }

      status = IotStatus.ready;
    } catch (_) {
      status = IotStatus.error;
    }
    notifyListeners();
  }

  // ================= 에어컨 =================

  Future<void> toggleAc() async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(isOn: !prev.isOn);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();

    // 켜거나 끌 때 상태 저장
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

    // 온도 변경 시 저장
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

    // 온도 변경 시 저장
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

  Future<void> setAcMode(AcMode m) async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(mode: m);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();

    // 모드 변경 시 저장 (핵심!)
    _saveCurrentSettings();

    try {
      await repo.setAcMode(m);
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: prev);
        notifyListeners();
      }
    }
  }

  // (타이머는 일회성이므로 저장하지 않음)
  Future<void> setAcTimer(int h) async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(timerHours: h);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();
    try {
      await repo.setAcTimer(h);
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: prev);
        notifyListeners();
      }
    }
  }

  Future<void> setAcFanSpeed(AcFanSpeed speed) async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(fanSpeed: speed);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();

    _saveCurrentSettings(); // 팬 속도도 저장

    try {
      await repo.setAcFanSpeed(speed);
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: prev);
        notifyListeners();
      }
    }
  }

  // (기타 메서드는 그대로 유지...)
  Future<void> toggleAcSwing() async { /* ... */ } // 기존 코드
  Future<void> toggleHrv() async { /* ... */ }     // 기존 코드
  Future<void> setBlinds(BlindsStatus st) async { /* ... */ } // 기존 코드
  Future<void> toggleLight(String room) async { /* ... */ }   // 기존 코드
  Future<void> setBrightness(String room, BrightnessLevel b) async { /* ... */ } // 기존 코드

  // =========================================================
  // ✅ [신규 기능] 설정 저장 및 복원 로직
  // =========================================================

  static const _keyMode = 'ac_last_mode_index';
  static const _keyTemp = 'ac_last_temp';
  static const _keyFan  = 'ac_last_fan_index';

  /// 현재 에어컨 설정을 기기 저장소에 저장
  Future<void> _saveCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMode, snapshot.aircon.mode.index);
    await prefs.setInt(_keyTemp, snapshot.aircon.temperature);
    await prefs.setInt(_keyFan, snapshot.aircon.fanSpeed.index);
  }

  /// 에어컨이 꺼져있을 때, 저장소에서 마지막 설정을 불러와 덮어씌움
  Future<void> _restoreLastSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final savedModeIdx = prefs.getInt(_keyMode);
    final savedTemp = prefs.getInt(_keyTemp);
    final savedFanIdx = prefs.getInt(_keyFan);

    AirconState newAc = snapshot.aircon;

    // 저장된 값이 있으면 적용 (없으면 기본값 유지)
    if (savedModeIdx != null && savedModeIdx < AcMode.values.length) {
      newAc = newAc.copyWith(mode: AcMode.values[savedModeIdx]);
    }
    if (savedTemp != null) {
      newAc = newAc.copyWith(temperature: savedTemp);
    }
    if (savedFanIdx != null && savedFanIdx < AcFanSpeed.values.length) {
      newAc = newAc.copyWith(fanSpeed: AcFanSpeed.values[savedFanIdx]);
    }

    // 화면 갱신
    snapshot = snapshot.copyWith(aircon: newAc);
  }
}