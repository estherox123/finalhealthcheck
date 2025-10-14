// lib/data/iot/mock_iot_api.dart
import 'dart:async';
import 'iot_api.dart';
import 'models.dart';

/// 네트워크/클라우드 없이 데모로 동작하는 Mock API
class MockIotApi implements IotApi {
  IotSnapshot _state = IotSnapshot.initial();

  Future<T> _latency<T>(T Function() body) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return body();
  }

  @override
  Future<IotSnapshot> fetchSnapshot() => _latency(() => _state);

  @override
  Future<AirconState> setAirconPower(bool on) => _latency(() {
    _state = _state.copyWith(aircon: _state.aircon.copyWith(isOn: on));
    return _state.aircon;
  });

  @override
  Future<AirconState> setAirconTemp(int temp) => _latency(() {
    final t = temp.clamp(16, 30);
    _state = _state.copyWith(aircon: _state.aircon.copyWith(temperature: t));
    return _state.aircon;
  });

  @override
  Future<AirconState> setAirconMode(AcMode mode) => _latency(() {
    _state = _state.copyWith(aircon: _state.aircon.copyWith(mode: mode));
    return _state.aircon;
  });

  @override
  Future<AirconState> setAirconTimer(int hours) => _latency(() {
    final allowed = {0, 1, 2, 4}.contains(hours) ? hours : 0;
    _state = _state.copyWith(aircon: _state.aircon.copyWith(timerHours: allowed));
    return _state.aircon;
  });

  @override
  Future<HrvState> setHrvPower(bool on) => _latency(() {
    _state = _state.copyWith(hrv: _state.hrv.copyWith(isOn: on));
    return _state.hrv;
  });

  @override
  Future<BlindsStatus> controlBlinds(BlindsStatus status) => _latency(() {
    _state = _state.copyWith(blinds: status);
    return _state.blinds;
  });

  @override
  Future<LightsState> toggleLight(String room) => _latency(() {
    final cur = _state.lights[room] ?? LightRoomState.off;
    final changed = cur.copyWith(isOn: !cur.isOn);
    final newMap = Map<String, LightRoomState>.from(_state.lights)..[room] = changed;
    _state = _state.copyWith(lights: newMap);
    return _state.lights;
  });

  @override
  Future<LightsState> setBrightness(String room, BrightnessLevel b) => _latency(() {
    final cur = _state.lights[room] ?? LightRoomState.off;
    final changed = cur.copyWith(brightness: b);
    final newMap = Map<String, LightRoomState>.from(_state.lights)..[room] = changed;
    _state = _state.copyWith(lights: newMap);
    return _state.lights;
  });
}
