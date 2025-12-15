// lib/data/iot/device_control_controller.dart
/// IoT 제어 상태관리 컨트롤러
/// 저장소에서 스냅샷 로드 후 에어컨·환기(HRV)·블라인드·조명 토글/설정 제공,
/// 상태(idle/loading/ready/error) 추적 및 변경 시 notifyListeners 호출

import 'package:flutter/foundation.dart';
import 'iot_repository.dart';
import 'models.dart';

enum IotStatus { idle, loading, ready, error }

class DeviceControlController extends ChangeNotifier {
  final IotRepository repo;

  IotStatus status = IotStatus.idle;
  IotSnapshot snapshot = IotSnapshot.initial();

  // 동시에 여러 번 눌렸을 때 오래된 응답이 나중 상태를 덮어쓰지 않도록
  // 제어 종류별로 시퀀스 번호를 관리한다.
  int _airconSeq = 0;
  int _hrvSeq = 0;
  int _blindsSeq = 0;
  int _lightsSeq = 0;

  DeviceControlController(this.repo);

  Future<void> init() async {
    status = IotStatus.loading;
    notifyListeners();
    try {
      snapshot = await repo.load();
      status = IotStatus.ready;
    } catch (_) {
      status = IotStatus.error;
    }
    notifyListeners();
  }

  // 에어컨
  Future<void> toggleAc() async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(isOn: !prev.isOn);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();
    try {
      final s = await repo.setAcPower(optimistic.isOn);
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: s);
        notifyListeners();
      }
    } catch (_) {
      if (seq == _airconSeq) {
        // 실패 시 이전 상태로 롤백
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
    try {
      await repo.setAcTemp(newTemp);
      // 응답 값은 사용하지 않고, 낙관적 UI 값을 유지한다.
      // (HA가 약간 늦게 갱신되어 이전 온도를 돌려주는 경우 롤백되는 현상 방지)
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: prev);
        notifyListeners();
      }
    }
  }

  Future<void> setAcMode(AcMode m) async {
    final seq = ++_airconSeq;
    final prev = snapshot.aircon;
    final optimistic = prev.copyWith(mode: m);
    snapshot = snapshot.copyWith(aircon: optimistic);
    notifyListeners();
    try {
      final s = await repo.setAcMode(m);
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: s);
        notifyListeners();
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
    try {
      final s = await repo.setAcTimer(h);
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: s);
        notifyListeners();
      }
    } catch (_) {
      if (seq == _airconSeq) {
        snapshot = snapshot.copyWith(aircon: prev);
        notifyListeners();
      }
    }
  }

  // HRV 환기
  Future<void> toggleHrv() async {
    final seq = ++_hrvSeq;
    final prev = snapshot.hrv;
    final optimistic = prev.copyWith(isOn: !prev.isOn);
    snapshot = snapshot.copyWith(hrv: optimistic);
    notifyListeners();
    try {
      final s = await repo.setHrv(optimistic.isOn);
      if (seq == _hrvSeq) {
        snapshot = snapshot.copyWith(hrv: s);
        notifyListeners();
      }
    } catch (_) {
      if (seq == _hrvSeq) {
        snapshot = snapshot.copyWith(hrv: prev);
        notifyListeners();
      }
    }
  }

  // 블라인드
  Future<void> setBlinds(BlindsStatus st) async {
    final seq = ++_blindsSeq;
    final prev = snapshot.blinds;
    snapshot = snapshot.copyWith(blinds: st);
    notifyListeners();
    try {
      final s = await repo.setBlinds(st);
      if (seq == _blindsSeq) {
        snapshot = snapshot.copyWith(blinds: s);
        notifyListeners();
      }
    } catch (_) {
      if (seq == _blindsSeq) {
        snapshot = snapshot.copyWith(blinds: prev);
        notifyListeners();
      }
    }
  }

  // 전등
  Future<void> toggleLight(String room) async {
    final seq = ++_lightsSeq;
    final prev = snapshot.lights;
    final cur = prev[room] ?? LightRoomState.off;
    final optimisticRoom = cur.copyWith(isOn: !cur.isOn);
    final optimisticMap = Map<String, LightRoomState>.from(prev)
      ..[room] = optimisticRoom;
    snapshot = snapshot.copyWith(lights: optimisticMap);
    notifyListeners();
    try {
      final m = await repo.toggleLight(room);
      if (seq == _lightsSeq) {
        snapshot = snapshot.copyWith(lights: m);
        notifyListeners();
      }
    } catch (_) {
      if (seq == _lightsSeq) {
        snapshot = snapshot.copyWith(lights: prev);
        notifyListeners();
      }
    }
  }

  Future<void> setBrightness(String room, BrightnessLevel b) async {
    final seq = ++_lightsSeq;
    final prev = snapshot.lights;
    final cur = prev[room] ?? LightRoomState.off;
    final optimisticRoom = cur.copyWith(brightness: b, isOn: true);
    final optimisticMap = Map<String, LightRoomState>.from(prev)
      ..[room] = optimisticRoom;
    snapshot = snapshot.copyWith(lights: optimisticMap);
    notifyListeners();
    try {
      final m = await repo.setBrightness(room, b);
      if (seq == _lightsSeq) {
        snapshot = snapshot.copyWith(lights: m);
        notifyListeners();
      }
    } catch (_) {
      if (seq == _lightsSeq) {
        snapshot = snapshot.copyWith(lights: prev);
        notifyListeners();
      }
    }
  }
}
