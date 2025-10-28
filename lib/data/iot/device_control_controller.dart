// lib/data/iot/device_control_controller.dart
import 'package:flutter/foundation.dart';
import 'iot_repository.dart';
import 'models.dart';

enum IotStatus { idle, loading, ready, error }

class DeviceControlController extends ChangeNotifier {
  final IotRepository repo;

  IotStatus status = IotStatus.idle;
  IotSnapshot snapshot = IotSnapshot.initial();

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
    final next = !snapshot.aircon.isOn;
    final s = await repo.setAcPower(next);
    snapshot = snapshot.copyWith(aircon: s);
    notifyListeners();
  }

  Future<void> acTempDelta(int d) async {
    final s = await repo.setAcTemp((snapshot.aircon.temperature + d));
    snapshot = snapshot.copyWith(aircon: s);
    notifyListeners();
  }

  Future<void> setAcMode(AcMode m) async {
    final s = await repo.setAcMode(m);
    snapshot = snapshot.copyWith(aircon: s);
    notifyListeners();
  }

  Future<void> setAcTimer(int h) async {
    final s = await repo.setAcTimer(h);
    snapshot = snapshot.copyWith(aircon: s);
    notifyListeners();
  }

  // HRV 환기
  Future<void> toggleHrv() async {
    final next = !snapshot.hrv.isOn;
    final s = await repo.setHrv(next);
    snapshot = snapshot.copyWith(hrv: s);
    notifyListeners();
  }

  // 블라인드
  Future<void> setBlinds(BlindsStatus st) async {
    final s = await repo.setBlinds(st);
    snapshot = snapshot.copyWith(blinds: s);
    notifyListeners();
  }

  // 전등
  Future<void> toggleLight(String room) async {
    final m = await repo.toggleLight(room);
    snapshot = snapshot.copyWith(lights: m);
    notifyListeners();
  }

  Future<void> setBrightness(String room, BrightnessLevel b) async {
    final m = await repo.setBrightness(room, b);
    snapshot = snapshot.copyWith(lights: m);
    notifyListeners();
  }
}
