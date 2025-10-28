// lib/data/iot/iot_repository.dart
import 'iot_api.dart';
import 'models.dart';

/// API 래퍼 + 캐싱/합성 책임
class IotRepository {
  final IotApi api;
  IotSnapshot? _cache;

  IotRepository(this.api);

  Future<IotSnapshot> load() async {
    _cache = await api.fetchSnapshot();
    return _cache!;
  }

  IotSnapshot? get snapshot => _cache;

  // 아래 메서드들은 캐시 갱신
  Future<AirconState> setAcPower(bool on) async {
    final s = await api.setAirconPower(on);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(aircon: s);
    return s;
  }

  Future<AirconState> setAcTemp(int temp) async {
    final s = await api.setAirconTemp(temp);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(aircon: s);
    return s;
  }

  Future<AirconState> setAcMode(AcMode m) async {
    final s = await api.setAirconMode(m);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(aircon: s);
    return s;
  }

  Future<AirconState> setAcTimer(int h) async {
    final s = await api.setAirconTimer(h);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(aircon: s);
    return s;
  }

  Future<HrvState> setHrv(bool on) async {
    final s = await api.setHrvPower(on);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(hrv: s);
    return s;
  }

  Future<BlindsStatus> setBlinds(BlindsStatus st) async {
    final s = await api.controlBlinds(st);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(blinds: s);
    return s;
  }

  Future<LightsState> toggleLight(String room) async {
    final m = await api.toggleLight(room);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(lights: m);
    return m;
  }

  Future<LightsState> setBrightness(String room, BrightnessLevel b) async {
    final m = await api.setBrightness(room, b);
    _cache = (_cache ?? IotSnapshot.initial()).copyWith(lights: m);
    return m;
  }
}
