// lib/data/iot/iot_repository.dart

import 'home_assistant_api.dart';
import 'models.dart';

class IotRepository {
  final HomeAssistantApi _api;
  IotSnapshot? _cache;

  IotRepository(this._api);

  Future<IotSnapshot> load() async {
    // ✅ [속도 최적화] 여기서 모든 데이터를 한 번에 당겨옵니다!
    // 이후의 fetch 호출들은 0ms에 가깝게 처리됩니다.
    await _api.preloadAllStates();

    // 2. 데이터 가져오기 (캐시에서 즉시 로딩)
    final results = await Future.wait([
      _api.fetchAirconState(_api.options.livingAcEntityId),
      _api.fetchAirconState(_api.options.bedroomAcEntityId),
      _api.fetchHrvState(_api.options.hrvEntityId ?? ''),
      _api.fetchAdminSettings(),
      _api.fetchInbodyData(),
      _api.fetchAirMonitorData(),
    ]);

    var livingAc = results[0] as AirconState;
    final bedroomAc = results[1] as AirconState;
    final hrv = results[2] as HrvState;
    final admin = results[3] as AdminSettings;
    final inbody = results[4] as Map<String, double>;
    final airData = results[5] as Map<String, dynamic>;

    // 에어컨 온습도 교체 (에어모니터 데이터 사용)
    final double airTemp = airData['temp'];
    final double airHum = airData['hum'];
    if (airTemp > 0 || airHum > 0) {
      livingAc = livingAc.copyWith(
        currentTemperature: airTemp > 0 ? airTemp : livingAc.currentTemperature,
        currentHumidity: airHum > 0 ? airHum : livingAc.currentHumidity,
      );
    }

    _cache = IotSnapshot.initial().copyWith(
      livingAc: livingAc,
      bedroomAc: bedroomAc,
      hrv: hrv,
      adminSettings: admin,

      // 폰 센서 데이터
      inbodyWeight: inbody['weight'],
      inbodyFat:    inbody['fat'],
      inbodyBMR:    inbody['bmr'],
      inbodyMuscle: inbody['muscle'],
      bpSystolic:   inbody['systolic'],
      bpDiastolic:  inbody['diastolic'],
      bpPulse:      inbody['pulse'],
      inbodyBMI:    inbody['bmi'],
      inbodyPBF:    inbody['pbf'],
      inbodyVFL:    inbody['vfl'],

      // 공기질 데이터
      co2: airData['co2'],
      pm1: airData['pm1'],
      pm25: airData['pm25'],
      pm10: airData['pm10'],
      odor: airData['odor'],
      airQuality: airData['airQuality'],
    );

    return _cache!;
  }

  IotSnapshot get snapshot => _cache ?? IotSnapshot.initial();

  // (Control 메서드들은 기존과 동일하게 유지 - 생략)
  String _getEntityId(AcLocation loc) { return loc == AcLocation.living ? _api.options.livingAcEntityId : _api.options.bedroomAcEntityId; }
  IotSnapshot _updateCacheAc(AcLocation loc, AirconState newState) { if (loc == AcLocation.living) { return (_cache ?? IotSnapshot.initial()).copyWith(livingAc: newState); } else { return (_cache ?? IotSnapshot.initial()).copyWith(bedroomAc: newState); } }
  Future<void> setAcPower(AcLocation loc, bool on) async { final eid = _getEntityId(loc); await _api.setAirconPower(eid, on); final newState = await _api.fetchAirconState(eid); _cache = _updateCacheAc(loc, newState); }
  Future<void> setAcTemp(AcLocation loc, int temp) async { final eid = _getEntityId(loc); await _api.setAirconTemp(eid, temp); final newState = await _api.fetchAirconState(eid); _cache = _updateCacheAc(loc, newState); }
  Future<void> setAcMode(AcLocation loc, AcMode mode) async { final eid = _getEntityId(loc); await _api.setAirconMode(eid, mode); final newState = await _api.fetchAirconState(eid); _cache = _updateCacheAc(loc, newState); }
  Future<void> setAcFanSpeed(AcLocation loc, AcFanSpeed speed) async { final eid = _getEntityId(loc); await _api.setAirconFanSpeed(eid, speed); final newState = await _api.fetchAirconState(eid); _cache = _updateCacheAc(loc, newState); }
  Future<void> setAcTimer(AcLocation loc, int hours) async { await _api.setAirconTimer(hours); final newState = await _api.fetchAirconState(_getEntityId(loc)); _cache = _updateCacheAc(loc, newState); }
  Future<void> setAcAutoMode(bool on) async { await _api.setAcAutoMode(on); await load(); }
  Future<void> setSeasonMode(String mode) async { await _api.setSeasonMode(mode); await load(); }
  Future<void> setAdminNumber(String suffix, double val) async { await _api.setAdminNumber(suffix, val); final newSettings = await _api.fetchAdminSettings(); _cache = (_cache ?? IotSnapshot.initial()).copyWith(adminSettings: newSettings); }
  Future<void> setHrvPower(bool on) async { final eid = _api.options.hrvEntityId ?? ''; if (eid.isEmpty) return; await _api.setHrvPower(eid, on); final newState = await _api.fetchHrvState(eid); _cache = (_cache ?? IotSnapshot.initial()).copyWith(hrv: newState); }
}