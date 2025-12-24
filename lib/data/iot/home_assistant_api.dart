// lib/data/iot/home_assistant_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'home_assistant_options.dart';
import 'iot_api.dart';
import 'models.dart';

class HomeAssistantApi implements IotApi {
  final HomeAssistantOptions options;
  final http.Client _client;
  int _lastTimerHours = 0;

  static const _timerEntity = 'timer.ac_sleep_timer';

  HomeAssistantApi({
    required this.options,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _base => options.baseUrl.endsWith('/')
      ? options.baseUrl
      : '${options.baseUrl}/';

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${options.token}',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _getState(String entityId) async {
    final res = await _client.get(Uri.parse('${_base}api/states/$entityId'),
        headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    // 에러 발생 시 로그 출력
    print('HA state 조회 실패(${res.statusCode}) for $entityId');
    return {};
  }

  Future<List<dynamic>> _callService(
      String domain, String service, Map<String, dynamic> data) async {
    final res = await _client.post(
      Uri.parse('${_base}api/services/$domain/$service'),
      headers: _headers,
      body: jsonEncode(data),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      print('HA service 실패($domain/$service): ${res.body}');
      throw Exception('HA Service Error');
    }
    if (res.body.isEmpty) return const [];
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is List) return decoded;
    } catch (_) {}
    return const [];
  }

  @override
  Future<IotSnapshot> fetchSnapshot() async {
    final results = await Future.wait([
      _fetchAircon(),
      _fetchHrv(),
      _fetchBlinds(),
      _fetchLights(),
    ]);

    return IotSnapshot(
      aircon: results[0] as AirconState,
      hrv: results[1] as HrvState,
      blinds: results[2] as BlindsStatus,
      lights: results[3] as LightsState,
    );
  }

  Future<AirconState> _fetchAircon() async {
    final data = await _getState(options.acEntityId);
    if (data.isEmpty) return AirconState.initial;

    final attrs = (data['attributes'] as Map?) ?? {};

    final rawState = data['state'] as String? ?? 'off';
    final isOn = rawState != 'off' && rawState != 'unavailable';
    final mode = _hvacModeToAc(rawState);

    final temp = (attrs['temperature'] ??
        attrs['target_temp_high'] ??
        attrs['target_temp_low']) as num? ??
        AirconState.initial.temperature;

    final curTemp = (attrs['current_temperature'] as num?)?.toDouble() ??
        AirconState.initial.currentTemperature;

    final fanModeStr = attrs['fan_mode'] as String?;
    final swingModeStr = attrs['swing_mode'] as String?;

    // 타이머 상태 확인
    try {
      final timerData = await _getState(_timerEntity);

      if (timerData.isNotEmpty && timerData['state'] == 'active') {
        final timerAttrs = (timerData['attributes'] as Map?) ?? {};
        final durationStr = timerAttrs['duration'] as String? ?? '0:00:00';
        final parts = durationStr.split(':');

        if (parts.isNotEmpty) {
          _lastTimerHours = int.tryParse(parts[0]) ?? 0;
        } else {
          _lastTimerHours = 1;
        }
        if (_lastTimerHours == 0) _lastTimerHours = 1; // 0이면 1로 표시
      } else {
        _lastTimerHours = 0;
      }
    } catch (_) {
      _lastTimerHours = 0;
    }

    return AirconState(
      isOn: isOn,
      temperature: temp.round().clamp(16, 30),
      currentTemperature: curTemp,
      mode: mode,
      timerHours: _lastTimerHours,
      fanSpeed: _mapHaFanToEnum(fanModeStr),
      isSwing: _mapHaSwingToBool(swingModeStr),
    );
  }

  // ... (Hrv, Blinds, Lights 관련 메서드는 기존과 동일) ...
  Future<HrvState> _fetchHrv() async {
    final id = options.hrvEntityId;
    if (id == null || id.isEmpty) return HrvState.initial;
    final data = await _getState(id);
    final isOn = (data['state'] as String? ?? 'off') != 'off';
    return HrvState(isOn: isOn);
  }

  Future<BlindsStatus> _fetchBlinds() async {
    final id = options.blindsEntityId;
    if (id == null || id.isEmpty) return BlindsStatus.stop;
    final data = await _getState(id);
    final state = (data['state'] as String? ?? '').toLowerCase();
    if (state == 'open' || state == 'opening') return BlindsStatus.open;
    if (state == 'closed' || state == 'closing') return BlindsStatus.close;
    return BlindsStatus.stop;
  }

  Future<LightsState> _fetchLights() async {
    final result = <String, LightRoomState>{};
    for (final entry in options.lightEntityIds.entries) {
      final room = entry.key;
      final id = entry.value;
      if (id.isEmpty) {
        result[room] = LightRoomState.off;
        continue;
      }
      final data = await _getState(id);
      final attrs = (data['attributes'] as Map?) ?? {};
      final isOn = (data['state'] as String? ?? 'off') != 'off';
      final brightness = (attrs['brightness'] as num?)?.toDouble() ?? 0;
      final level = _brightnessToLevel(brightness);
      result[room] = LightRoomState(isOn: isOn, brightness: level);
    }
    return result;
  }

  @override
  Future<AirconState> setAirconPower(bool on) async {
    final result = await _callService('climate', on ? 'turn_on' : 'turn_off', {
      'entity_id': options.acEntityId,
    });

    // 에어컨 끌 때 타이머도 같이 취소
    if (!on) {
      try {
        await _callService('timer', 'cancel', {'entity_id': _timerEntity});
      } catch (e) {
        print('타이머 취소 실패: $e');
      }
      _lastTimerHours = 0;
    }

    return _parseResultOrFetch(result);
  }

  @override
  Future<AirconState> setAirconTemp(int temp) async {
    final t = temp.clamp(16, 30);
    final result = await _callService('climate', 'set_temperature', {
      'entity_id': options.acEntityId,
      'temperature': t,
    });
    return _parseResultOrFetch(result);
  }

  @override
  Future<AirconState> setAirconMode(AcMode mode) async {
    final result = await _callService('climate', 'set_hvac_mode', {
      'entity_id': options.acEntityId,
      'hvac_mode': _acToHvacMode(mode),
    });
    return _parseResultOrFetch(result);
  }

  @override
  Future<AirconState> setAirconTimer(int hours) async {
    if (hours == 0) {
      await _callService('timer', 'cancel', {'entity_id': _timerEntity});
      _lastTimerHours = 0;
    } else {
      final duration = '$hours:00:00';
      await _callService('timer', 'start', {
        'entity_id': _timerEntity,
        'duration': duration,
      });
      _lastTimerHours = hours;
    }

    final cur = await _fetchAircon();
    return cur.copyWith(timerHours: _lastTimerHours);
  }

  @override
  Future<AirconState> setAirconFanSpeed(AcFanSpeed speed) async {
    final result = await _callService('climate', 'set_fan_mode', {
      'entity_id': options.acEntityId,
      'fan_mode': _mapEnumToHaFan(speed),
    });
    return _parseResultOrFetch(result);
  }

  @override
  Future<AirconState> setAirconSwing(bool isSwing) async {
    final modeStr = isSwing ? 'on' : 'off';
    final result = await _callService('climate', 'set_swing_mode', {
      'entity_id': options.acEntityId,
      'swing_mode': modeStr,
    });
    return _parseResultOrFetch(result);
  }

  @override
  Future<HrvState> setHrvPower(bool on) async {
    final id = options.hrvEntityId;
    if (id == null || id.isEmpty) return HrvState(isOn: on);
    await _callService('fan', on ? 'turn_on' : 'turn_off', {'entity_id': id});
    return _fetchHrv();
  }

  @override
  Future<BlindsStatus> controlBlinds(BlindsStatus status) async {
    final id = options.blindsEntityId;
    if (id == null || id.isEmpty) return status;
    switch (status) {
      case BlindsStatus.open: await _callService('cover', 'open_cover', {'entity_id': id}); break;
      case BlindsStatus.close: await _callService('cover', 'close_cover', {'entity_id': id}); break;
      case BlindsStatus.stop: await _callService('cover', 'stop_cover', {'entity_id': id}); break;
    }
    return _fetchBlinds();
  }

  @override
  Future<LightsState> toggleLight(String room) async {
    final id = options.lightEntityIds[room];
    if (id == null || id.isEmpty) return _fetchLights();
    await _callService('light', 'toggle', {'entity_id': id});
    return _fetchLights();
  }

  @override
  Future<LightsState> setBrightness(String room, BrightnessLevel b) async {
    final id = options.lightEntityIds[room];
    if (id == null || id.isEmpty) return _fetchLights();
    await _callService('light', 'turn_on', {'entity_id': id, 'brightness_pct': _brightnessLevelToPct(b)});
    return _fetchLights();
  }

  Future<AirconState> _parseResultOrFetch(List<dynamic> result) async {
    final parsed = _airconFromServiceResult(result);
    if (parsed != null) return parsed;
    return _fetchAircon();
  }

  AirconState? _airconFromServiceResult(List<dynamic> result) {
    if (result.isEmpty) return null;
    final first = result.first;
    if (first is! Map) return null;
    final map = Map<String, dynamic>.from(first as Map);

    final rawState = map['state'] as String? ?? 'off';
    final isOn = rawState != 'off' && rawState != 'unavailable';
    final mode = _hvacModeToAc(rawState);

    final attrs = (map['attributes'] as Map?) ?? {};
    final temp = (attrs['temperature'] ?? attrs['target_temp_high'] ?? attrs['target_temp_low']) as num? ?? AirconState.initial.temperature;
    final curTemp = (attrs['current_temperature'] as num?)?.toDouble() ?? AirconState.initial.currentTemperature;
    final hum = (attrs['humidity'] ?? attrs['current_humidity']) as num? ?? AirconState.initial.currentHumidity;

    return AirconState(
      isOn: isOn,
      temperature: temp.round().clamp(16, 30),
      currentTemperature: curTemp,
      currentHumidity: hum.toDouble(),
      mode: mode,
      timerHours: _lastTimerHours,
      fanSpeed: _mapHaFanToEnum(attrs['fan_mode'] as String?),
      isSwing: _mapHaSwingToBool(attrs['swing_mode'] as String?),
    );
  }

  AcMode _hvacModeToAc(String hvacMode) {
    switch (hvacMode) {
      case 'heat': return AcMode.heat;
      case 'fan_only': case 'fan': return AcMode.fan;
      case 'dry': return AcMode.dry;
      case 'auto': return AcMode.auto;
      case 'cool': default: return AcMode.cool;
    }
  }

  String _acToHvacMode(AcMode mode) {
    switch (mode) {
      case AcMode.heat: return 'heat';
      case AcMode.fan: return 'fan_only';
      case AcMode.dry: return 'dry';
      case AcMode.auto: return 'auto';
      case AcMode.cool: default: return 'cool';
    }
  }

  BrightnessLevel _brightnessToLevel(double raw) {
    if (raw >= 170) return BrightnessLevel.bright;
    if (raw >= 85) return BrightnessLevel.normal;
    return BrightnessLevel.dim;
  }

  int _brightnessLevelToPct(BrightnessLevel b) {
    switch (b) {
      case BrightnessLevel.dim: return 30;
      case BrightnessLevel.normal: return 60;
      case BrightnessLevel.bright: return 90;
    }
  }

  AcFanSpeed _mapHaFanToEnum(String? mode) {
    if (mode == null) return AcFanSpeed.auto;
    switch (mode.toLowerCase()) {
      case 'low': return AcFanSpeed.low;
      case 'medium': case 'mid': return AcFanSpeed.medium;
      case 'high': return AcFanSpeed.high;
      case 'auto': default: return AcFanSpeed.auto;
    }
  }

  String _mapEnumToHaFan(AcFanSpeed speed) {
    switch (speed) {
      case AcFanSpeed.low: return 'low';
      case AcFanSpeed.medium: return 'medium';
      case AcFanSpeed.high: return 'high';
      case AcFanSpeed.auto: default: return 'auto';
    }
  }

  bool _mapHaSwingToBool(String? mode) {
    if (mode == null) return false;
    return mode.toLowerCase() != 'off';
  }
}