// lib/data/iot/home_assistant_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'home_assistant_options.dart';
import 'models.dart';

class HomeAssistantApi {
  final HomeAssistantOptions options;
  final http.Client _client;
  // 전체 상태 캐시 (속도 향상용)
  Map<String, dynamic> _stateCache = {};

  static const _timerEntity = 'timer.ac_sleep_timer';
  static const _autoModeEntity = 'input_boolean.ac_full_auto_mode';
  static const _seasonModeEntity = 'input_select.hvac_season_mode';

  HomeAssistantApi({
    required this.options,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _base => options.baseUrl.endsWith('/') ? options.baseUrl : '${options.baseUrl}/';

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${options.token}',
    'Content-Type': 'application/json',
  };

  // ================= Bulk Load (속도 최적화) =================
  Future<void> preloadAllStates() async {
    try {
      final res = await _client.get(Uri.parse('${_base}api/states'), headers: _headers);
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        _stateCache.clear();
        for (var item in list) {
          _stateCache[item['entity_id']] = item;
        }
      }
    } catch (e) { print("Preload Error: $e"); }
  }

  // ================= Public Fetch Methods =================

  /// 에어컨 상태 조회
  Future<AirconState> fetchAirconState(String entityId) async {
    final data = await _getState(entityId);
    final autoData = await _getState(_autoModeEntity);
    final isAuto = (autoData['state'] == 'on');

    if (data.isEmpty) return AirconState.initial.copyWith(isAutoMode: isAuto);

    final attrs = (data['attributes'] as Map?) ?? {};
    final rawState = data['state'] as String? ?? 'off';
    final isOn = rawState != 'off' && rawState != 'unavailable';
    final mode = _hvacModeToAc(rawState);

    final temp = (attrs['temperature'] ?? attrs['target_temp_high'] ?? attrs['target_temp_low']) as num? ?? 24;
    final curTemp = (attrs['current_temperature'] as num?)?.toDouble() ?? 0.0;

    // 기본 습도 (Repository에서 에어모니터 값으로 교체됨)
    double humidity = 0.0;
    if (attrs.containsKey('current_humidity')) {
      humidity = (attrs['current_humidity'] as num).toDouble();
    } else if (attrs.containsKey('humidity')) {
      humidity = (attrs['humidity'] as num).toDouble();
    }

    int timerHours = 0;
    try {
      final timerData = await _getState(_timerEntity);
      if (timerData.isNotEmpty && timerData['state'] == 'active') {
        final durationStr = (timerData['attributes'] as Map?)?['duration'] as String? ?? '0:00:00';
        timerHours = int.tryParse(durationStr.split(':').first) ?? 0;
        if (timerHours == 0) timerHours = 1;
      }
    } catch (_) {}

    return AirconState(
      isOn: isOn, temperature: temp.round().clamp(16, 30), currentTemperature: curTemp, currentHumidity: humidity,
      mode: mode, timerHours: timerHours, fanSpeed: _mapHaFanToEnum(attrs['fan_mode'] as String?), isSwing: _mapHaSwingToBool(attrs['swing_mode'] as String?), isAutoMode: isAuto,
    );
  }

  /// 에어모니터 데이터 8종 가져오기
  Future<Map<String, dynamic>> fetchAirMonitorData() async {
    final temp = await _getDoubleState(options.airTempEntityId);
    final hum = await _getDoubleState(options.airHumEntityId);
    final co2 = await _getDoubleState(options.airCo2EntityId);
    final pm1 = await _getDoubleState(options.airPm1EntityId);
    final pm25 = await _getDoubleState(options.airPm25EntityId);
    final pm10 = await _getDoubleState(options.airPm10EntityId);
    final odor = await _getDoubleState(options.airOdorEntityId);
    final airQual = await _getDoubleState(options.airQualityEntityId);

    return {
      'temp': temp, 'hum': hum, 'co2': co2.toInt(),
      'pm1': pm1, 'pm25': pm25, 'pm10': pm10,
      'odor': odor.toInt(), 'airQuality': airQual.toInt(),
    };
  }

  Future<AdminSettings> fetchAdminSettings() async {
    final values = await Future.wait([
      _getStringState(_seasonModeEntity, 'Auto (사계절 감지)'), _getDoubleState('input_number.admin_summer_trigger_temp'), _getDoubleState('input_number.admin_summer_target_temp'),
      _getDoubleState('input_number.admin_winter_trigger_temp'), _getDoubleState('input_number.admin_winter_target_temp'), _getDoubleState('input_number.admin_humidity_trigger'), _getDoubleState('input_number.admin_humidity_target'),
    ]);
    return AdminSettings(seasonMode: values[0] as String, summerTriggerTemp: values[1] as double, summerTargetTemp: values[2] as double, winterTriggerTemp: values[3] as double, winterTargetTemp: values[4] as double, humidityTrigger: values[5] as double, humidityTarget: values[6] as double);
  }

  Future<Map<String, double>> fetchInbodyData() async {
    final prefix = options.healthSensorPrefix;
    final results = await Future.wait([ _getDoubleState('${prefix}weight'), _getDoubleState('${prefix}body_fat'), _getDoubleState('${prefix}basal_metabolic_rate'), Future.value(0.0), _getDoubleState('${prefix}systolic_blood_pressure'), _getDoubleState('${prefix}diastolic_blood_pressure'), _getDoubleState('${prefix}heart_rate') ]);
    double weight = results[0]; if (weight > 1000) weight = weight / 1000;
    double pbf = results[1]; double fatMass = 0.0; if (weight > 0 && pbf > 0) fatMass = weight * (pbf / 100);
    double bmi = 0.0; if (weight > 0) bmi = weight / (1.75 * 1.75);
    return { 'weight': weight, 'pbf': pbf, 'fat': fatMass, 'bmi': bmi, 'bmr': results[2], 'muscle': 0.0, 'vfl': 0.0, 'systolic': results[4], 'diastolic': results[5], 'pulse': results[6] };
  }

  Future<HrvState> fetchHrvState(String entityId) async { if (entityId.isEmpty) return HrvState.initial; final data = await _getState(entityId); return HrvState(isOn: (data['state'] as String? ?? 'off') != 'off'); }
  Future<List<Map<String, dynamic>>> fetchHistory(String entityId, {int days = 30}) async { if (entityId.isEmpty) return []; final now = DateTime.now(); final startTime = now.subtract(Duration(days: days)); final timestamp = startTime.toIso8601String(); final uri = Uri.parse('${_base}api/history/period/$timestamp').replace(queryParameters: {'filter_entity_id': entityId, 'end_time': now.toIso8601String(), 'minimal_response': 'true'}); try { final res = await _client.get(uri, headers: _headers); if (res.statusCode == 200) { final list = jsonDecode(res.body); if (list.isNotEmpty && list[0] is List) return List<Map<String, dynamic>>.from(list[0]); } } catch (_) {} return []; }

  // ================= Control Methods =================

  Future<void> setAirconPower(String entityId, bool on) async { await _callService('climate', on ? 'turn_on' : 'turn_off', {'entity_id': entityId}); if (!on) { try { await _callService('timer', 'cancel', {'entity_id': _timerEntity}); } catch (_) {} } }
  Future<void> setAirconTemp(String entityId, int temp) async { await _callService('climate', 'set_temperature', {'entity_id': entityId, 'temperature': temp}); }
  Future<void> setAirconMode(String entityId, AcMode mode) async { await _callService('climate', 'set_hvac_mode', {'entity_id': entityId, 'hvac_mode': _acToHvacMode(mode)}); }
  Future<void> setAirconFanSpeed(String entityId, AcFanSpeed speed) async { await _callService('climate', 'set_fan_mode', {'entity_id': entityId, 'fan_mode': _mapEnumToHaFan(speed)}); }
  Future<void> setAirconTimer(int hours) async { if (hours == 0) { await _callService('timer', 'cancel', {'entity_id': _timerEntity}); } else { await _callService('timer', 'start', {'entity_id': _timerEntity, 'duration': '$hours:00:00'}); } }
  Future<void> setAcAutoMode(bool on) async { await _callService('input_boolean', on ? 'turn_on' : 'turn_off', {'entity_id': _autoModeEntity}); }

  // ✅ [수정완료] 변수명 오타 수정
  Future<void> setAdminNumber(String suffix, double val) async {
    await _callService('input_number', 'set_value', {
      'entity_id': 'input_number.$suffix',
      'value': val
    });
  }

  Future<void> setSeasonMode(String mode) async { await _callService('input_select', 'select_option', {'entity_id': _seasonModeEntity, 'option': mode}); }
  Future<void> setHrvPower(String entityId, bool on) async { String domain = 'switch'; if (entityId.startsWith('fan.')) domain = 'fan'; await _callService(domain, on ? 'turn_on' : 'turn_off', {'entity_id': entityId}); }

  // ================= Helpers =================
  Future<Map<String, dynamic>> _getState(String entityId) async { if (_stateCache.containsKey(entityId)) return _stateCache[entityId]!; try { final res = await _client.get(Uri.parse('${_base}api/states/$entityId'), headers: _headers); if (res.statusCode == 200) { final d = jsonDecode(res.body) as Map<String, dynamic>; _stateCache[entityId] = d; return d; } return {}; } catch (_) { return {}; } }
  Future<double> _getDoubleState(String entityId) async { final data = await _getState(entityId); if (data.isEmpty) return 0.0; return double.tryParse(data['state'] as String? ?? '') ?? 0.0; }
  Future<String> _getStringState(String entityId, String defValue) async { final data = await _getState(entityId); return data['state'] as String? ?? defValue; }
  Future<void> _callService(String domain, String service, Map<String, dynamic> data) async { await _client.post(Uri.parse('${_base}api/services/$domain/$service'), headers: _headers, body: jsonEncode(data)); }

  Future<void> callService({required String domain, required String service, required String entityId, Map<String, dynamic>? data}) async {
    await _callService(domain, service, {'entity_id': entityId, ...?data});
  }

  AcMode _hvacModeToAc(String m) { switch (m) { case 'heat': return AcMode.heat; case 'fan_only': case 'fan': return AcMode.fan; case 'dry': return AcMode.dry; case 'auto': return AcMode.auto; default: return AcMode.cool; } }
  String _acToHvacMode(AcMode m) { switch (m) { case AcMode.heat: return 'heat'; case AcMode.fan: return 'fan_only'; case AcMode.dry: return 'dry'; case AcMode.auto: return 'auto'; default: return 'cool'; } }
  AcFanSpeed _mapHaFanToEnum(String? m) { switch (m?.toLowerCase()) { case 'low': return AcFanSpeed.low; case 'medium': case 'mid': return AcFanSpeed.medium; case 'high': return AcFanSpeed.high; default: return AcFanSpeed.auto; } }
  String _mapEnumToHaFan(AcFanSpeed s) { switch (s) { case AcFanSpeed.low: return 'low'; case AcFanSpeed.medium: return 'medium'; case AcFanSpeed.high: return 'high'; default: return 'auto'; } }
  bool _mapHaSwingToBool(String? m) => m != null && m.toLowerCase() != 'off';
}