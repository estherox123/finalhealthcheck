// lib/data/iot/device_control_controller.dart

import 'dart:async';
import 'package:flutter/material.dart';
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

      // 거실 에어컨 상태 복원/저장
      if (!snapshot.livingAc.isOn) {
        await _restoreLastSettings(AcLocation.living);
      } else {
        await _saveCurrentSettings(AcLocation.living);
      }

      // 안방 에어컨 상태 복원/저장
      if (!snapshot.bedroomAc.isOn) {
        await _restoreLastSettings(AcLocation.bedroom);
      } else {
        await _saveCurrentSettings(AcLocation.bedroom);
      }

      status = IotStatus.ready;
    } catch (_) {
      status = IotStatus.error;
    }
    notifyListeners();
  }

  // ================= UI 헬퍼 (배경색) =================

  /// 에어컨 상태(모드/전원)에 따른 배경색 반환
  Color getUiColor(AcMode mode) {
    // 꺼짐 상태 처리는 UI 쪽에서 state.isOn 체크 후 호출 권장
    switch (mode) {
      case AcMode.heat: return const Color(0xFFFFF3E0); // 난방
      case AcMode.cool: return const Color(0xFFE3F2FD); // 냉방
      case AcMode.dry:  return const Color(0xFFF3E5F5); // 제습
      case AcMode.fan:  return const Color(0xFFE8F5E9); // 송풍
      case AcMode.auto: return const Color(0xFFE0F2F1); // 자동
    }
  }

  /// 슬라이더 등 활성 색상
  Color getActiveColor(AcMode mode) {
    switch (mode) {
      case AcMode.heat: return Colors.orange;
      case AcMode.cool: return Colors.blue;
      case AcMode.dry:  return Colors.purple;
      case AcMode.fan:  return Colors.green;
      case AcMode.auto: return Colors.teal;
    }
  }

  // ================= 헬퍼: 스냅샷 갱신 =================

  // 위치에 따라 적절한 AirconState를 업데이트하여 새 스냅샷을 만듦
  IotSnapshot _updateAcSnapshot(AcLocation loc, AirconState newAcState) {
    if (loc == AcLocation.living) {
      return snapshot.copyWith(livingAc: newAcState);
    } else {
      return snapshot.copyWith(bedroomAc: newAcState);
    }
  }

  AirconState _getAcState(AcLocation loc) {
    return loc == AcLocation.living ? snapshot.livingAc : snapshot.bedroomAc;
  }

  // ================= 에어컨 제어 로직 =================

  Future<void> toggleAc(AcLocation loc) async {
    final seq = ++_airconSeq;
    final prev = _getAcState(loc);
    final optimistic = prev.copyWith(isOn: !prev.isOn);

    snapshot = _updateAcSnapshot(loc, optimistic);
    notifyListeners();

    _saveCurrentSettings(loc);

    try {
      await repo.setAcPower(loc, optimistic.isOn); // Repo도 location 지원 필요
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = _updateAcSnapshot(loc, prev); // 롤백
        notifyListeners();
      }
    }
  }

  Future<void> setTargetTemperature(AcLocation loc, double val) async {
    final int target = val.toInt().clamp(18, 30);
    final currentAc = _getAcState(loc);
    if (target == currentAc.temperature) return;

    final seq = ++_airconSeq;
    final prev = currentAc;
    final optimistic = prev.copyWith(temperature: target);

    snapshot = _updateAcSnapshot(loc, optimistic);
    notifyListeners();

    _saveCurrentSettings(loc);

    if (_tempDebounceTimer?.isActive ?? false) _tempDebounceTimer!.cancel();
    _tempDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await repo.setAcTemp(loc, target);
      } catch (_) {
        if (seq == _airconSeq) {
          snapshot = _updateAcSnapshot(loc, prev);
          notifyListeners();
        }
      }
    });
  }

  Future<void> setAcMode(AcLocation loc, AcMode newMode) async {
    final currentAc = _getAcState(loc);
    if (currentAc.mode == newMode) return;

    final seq = ++_airconSeq;
    final prev = currentAc;

    // 해당 모드의 마지막 저장 온도 불러오기
    final savedTemp = await _getSavedTempForMode(loc, newMode);

    final optimistic = prev.copyWith(
      mode: newMode,
      temperature: savedTemp,
    );

    snapshot = _updateAcSnapshot(loc, optimistic);
    notifyListeners();

    _saveCurrentSettings(loc);

    try {
      await repo.setAcMode(loc, newMode);
      if (prev.temperature != savedTemp) {
        await repo.setAcTemp(loc, savedTemp);
      }
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = _updateAcSnapshot(loc, prev);
        notifyListeners();
      }
    }
  }

  Future<void> setAcFanSpeed(AcLocation loc, AcFanSpeed speed) async {
    final seq = ++_airconSeq;
    final prev = _getAcState(loc);
    final optimistic = prev.copyWith(fanSpeed: speed);

    snapshot = _updateAcSnapshot(loc, optimistic);
    notifyListeners();

    _saveCurrentSettings(loc);

    try { await repo.setAcFanSpeed(loc, speed); } catch (_) {
      snapshot = _updateAcSnapshot(loc, prev);
      notifyListeners();
    }
  }

  Future<void> setAcTimer(AcLocation loc, int h) async {
    final seq = ++_airconSeq;
    final prev = _getAcState(loc);
    final optimistic = prev.copyWith(timerHours: h);

    snapshot = _updateAcSnapshot(loc, optimistic);
    notifyListeners();

    // 타이머는 서버 로직이거나 앱 로컬 로직일 수 있음. 일단 Repo 호출
    try { await repo.setAcTimer(loc, h); } catch (_) {
      if (seq == _airconSeq) {
        snapshot = _updateAcSnapshot(loc, prev);
        notifyListeners();
      }
    }
  }

  // ================= 환기 제어 =================
  Future<void> toggleHrv() async {
    final prev = snapshot.hrv.isOn;
    snapshot = snapshot.copyWith(hrv: snapshot.hrv.copyWith(isOn: !prev));
    notifyListeners();
    try {
      await repo.setHrvPower(!prev);
    } catch (_) {
      snapshot = snapshot.copyWith(hrv: snapshot.hrv.copyWith(isOn: prev));
      notifyListeners();
    }
  }

  // (조명, 블라인드 메서드는 현재 미사용이므로 생략 가능하나 틀은 유지)
  Future<void> setBlinds(BlindsStatus st) async {}
  Future<void> toggleLight(String room) async {}
  Future<void> setBrightness(String room, BrightnessLevel b) async {}


  // =========================================================
  // 모드별 온도 저장 및 복원 로직 (위치별 분리)
  // =========================================================

  // Key 생성 헬퍼: "living_ac_temp_cool", "bedroom_ac_last_mode_idx" 등
  String _key(AcLocation loc, String suffix) => '${loc.name}_$suffix';

  int _defaultTempFor(AcMode m) {
    switch (m) {
      case AcMode.heat: return 26;
      case AcMode.cool: return 24;
      case AcMode.dry: return 24;
      default: return 24;
    }
  }

  Future<int> _getSavedTempForMode(AcLocation loc, AcMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    // 예: living_ac_temp_cool
    return prefs.getInt(_key(loc, 'ac_temp_${mode.name}')) ?? _defaultTempFor(mode);
  }

  Future<void> _saveCurrentSettings(AcLocation loc) async {
    final prefs = await SharedPreferences.getInstance();
    final ac = _getAcState(loc);

    await prefs.setInt(_key(loc, 'ac_last_mode_idx'), ac.mode.index);
    await prefs.setInt(_key(loc, 'ac_last_fan_idx'), ac.fanSpeed.index);
    // 모드별 온도 저장
    await prefs.setInt(_key(loc, 'ac_temp_${ac.mode.name}'), ac.temperature);
  }

  Future<void> _restoreLastSettings(AcLocation loc) async {
    final prefs = await SharedPreferences.getInstance();
    final savedModeIdx = prefs.getInt(_key(loc, 'ac_last_mode_idx'));
    final savedFanIdx = prefs.getInt(_key(loc, 'ac_last_fan_idx'));

    AirconState newAc = _getAcState(loc);

    if (savedModeIdx != null && savedModeIdx < AcMode.values.length) {
      newAc = newAc.copyWith(mode: AcMode.values[savedModeIdx]);
    }
    if (savedFanIdx != null && savedFanIdx < AcFanSpeed.values.length) {
      newAc = newAc.copyWith(fanSpeed: AcFanSpeed.values[savedFanIdx]);
    }

    final savedTemp = prefs.getInt(_key(loc, 'ac_temp_${newAc.mode.name}'));
    if (savedTemp != null) {
      newAc = newAc.copyWith(temperature: savedTemp);
    } else {
      newAc = newAc.copyWith(temperature: _defaultTempFor(newAc.mode));
    }

    snapshot = _updateAcSnapshot(loc, newAc);
  }
}