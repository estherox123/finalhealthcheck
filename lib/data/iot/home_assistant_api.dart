import 'dart:convert';

import 'package:http/http.dart' as http;

import 'home_assistant_options.dart';
import 'iot_api.dart';
import 'models.dart';

/// Home Assistant REST API 기반 구현.
/// - 모든 호출은 Long-Lived Token 기반 Bearer 인증을 사용.
/// - timerHours 는 HA 기본 엔티티에 직접 대응되지 않아, 요청값을 그대로 반영한 상태만 리턴합니다.
class HomeAssistantApi implements IotApi {
  final HomeAssistantOptions options;
  final http.Client _client;
  int _lastTimerHours = 0; // HA에 직접 매핑되지 않는 타이머 UI 상태용

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
    final res =
        await _client.get(Uri.parse('${_base}api/states/$entityId'), headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('HA state 조회 실패(${res.statusCode}) for $entityId');
  }

  Future<void> _callService(String domain, String service, Map<String, dynamic> data) async {
    final res = await _client.post(
      Uri.parse('${_base}api/services/$domain/$service'),
      headers: _headers,
      body: jsonEncode(data),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HA service 실패($domain/$service): ${res.body}');
    }
  }

  /* ----------------------------- Snapshot ----------------------------- */
  @override
  Future<IotSnapshot> fetchSnapshot() async {
    final aircon = await _fetchAircon();
    final hrv = await _fetchHrv();
    final blinds = await _fetchBlinds();
    final lights = await _fetchLights();

    return IotSnapshot(
      aircon: aircon,
      hrv: hrv,
      blinds: blinds,
      lights: lights,
    );
  }

  Future<AirconState> _fetchAircon() async {
    final data = await _getState(options.acEntityId);
    final attrs = (data['attributes'] as Map?) ?? {};
    final hvacMode = (attrs['hvac_mode'] ?? attrs['preset_mode'] ?? '') as String? ?? 'off';
    final temp = (attrs['temperature'] ?? attrs['target_temp_high'] ?? attrs['target_temp_low'])
            as num? ??
        AirconState.initial.temperature;
    final mode = _hvacModeToAc(hvacMode);
    final isOn = (data['state'] as String? ?? 'off') != 'off';
    return AirconState(
      isOn: isOn,
      temperature: temp.round().clamp(16, 30),
      mode: mode,
      timerHours: _lastTimerHours,
    );
  }

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

  /* ----------------------------- Aircon ----------------------------- */
  @override
  Future<AirconState> setAirconPower(bool on) async {
    await _callService('climate', on ? 'turn_on' : 'turn_off', {
      'entity_id': options.acEntityId,
    });
    return _fetchAircon();
  }

  @override
  Future<AirconState> setAirconTemp(int temp) async {
    final t = temp.clamp(16, 30);
    await _callService('climate', 'set_temperature', {
      'entity_id': options.acEntityId,
      'temperature': t,
    });
    return _fetchAircon();
  }

  @override
  Future<AirconState> setAirconMode(AcMode mode) async {
    await _callService('climate', 'set_hvac_mode', {
      'entity_id': options.acEntityId,
      'hvac_mode': _acToHvacMode(mode),
    });
    return _fetchAircon();
  }

  @override
  Future<AirconState> setAirconTimer(int hours) async {
    // HA 기본 climate 엔티티에 타이머가 없으므로 UI 상태만 보존.
    final allowed = {0, 1, 2, 4}.contains(hours) ? hours : 0;
    _lastTimerHours = allowed;
    final cur = await _fetchAircon();
    return cur.copyWith(timerHours: allowed);
  }

  /* ----------------------------- HRV ----------------------------- */
  @override
  Future<HrvState> setHrvPower(bool on) async {
    final id = options.hrvEntityId;
    if (id == null || id.isEmpty) return HrvState(isOn: on);
    await _callService('fan', on ? 'turn_on' : 'turn_off', {
      'entity_id': id,
    });
    return _fetchHrv();
  }

  /* ----------------------------- Blinds ----------------------------- */
  @override
  Future<BlindsStatus> controlBlinds(BlindsStatus status) async {
    final id = options.blindsEntityId;
    if (id == null || id.isEmpty) return status;
    switch (status) {
      case BlindsStatus.open:
        await _callService('cover', 'open_cover', {'entity_id': id});
        break;
      case BlindsStatus.close:
        await _callService('cover', 'close_cover', {'entity_id': id});
        break;
      case BlindsStatus.stop:
        await _callService('cover', 'stop_cover', {'entity_id': id});
        break;
    }
    return _fetchBlinds();
  }

  /* ----------------------------- Lights ----------------------------- */
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
    await _callService('light', 'turn_on', {
      'entity_id': id,
      'brightness_pct': _brightnessLevelToPct(b),
    });
    return _fetchLights();
  }

  /* ----------------------------- Helpers ----------------------------- */
  AcMode _hvacModeToAc(String hvacMode) {
    switch (hvacMode) {
      case 'heat':
        return AcMode.heat;
      case 'fan_only':
      case 'fan':
        return AcMode.fan;
      case 'cool':
      default:
        return AcMode.cool;
    }
  }

  String _acToHvacMode(AcMode mode) {
    switch (mode) {
      case AcMode.heat:
        return 'heat';
      case AcMode.fan:
        return 'fan_only';
      case AcMode.cool:
      default:
        return 'cool';
    }
  }

  BrightnessLevel _brightnessToLevel(double raw) {
    if (raw >= 170) return BrightnessLevel.bright;
    if (raw >= 85) return BrightnessLevel.normal;
    return BrightnessLevel.dim;
  }

  int _brightnessLevelToPct(BrightnessLevel b) {
    switch (b) {
      case BrightnessLevel.dim:
        return 30;
      case BrightnessLevel.normal:
        return 60;
      case BrightnessLevel.bright:
        return 90;
    }
  }
}

