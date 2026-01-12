// lib/data/iot/home_assistant_options.dart

class HomeAssistantOptions {
  final String baseUrl;
  final String token;
  final String livingAcEntityId;
  final String bedroomAcEntityId;
  final String healthSensorPrefix;

  // ✅ [수정] 삼성 에어모니터 플러스 센서 ID들 (8종)
  final String airTempEntityId;
  final String airHumEntityId;
  final String airCo2EntityId;
  final String airPm1EntityId;
  final String airPm25EntityId;
  final String airPm10EntityId;
  final String airOdorEntityId;
  final String airQualityEntityId;

  final String? hrvEntityId;
  final String? blindsEntityId;
  final Map<String, String> lightEntityIds;

  const HomeAssistantOptions({
    required this.baseUrl,
    required this.token,
    required this.livingAcEntityId,
    required this.bedroomAcEntityId,
    required this.healthSensorPrefix,

    // 생성자에 추가
    required this.airTempEntityId,
    required this.airHumEntityId,
    required this.airCo2EntityId,
    required this.airPm1EntityId,
    required this.airPm25EntityId,
    required this.airPm10EntityId,
    required this.airOdorEntityId,
    required this.airQualityEntityId,

    this.hrvEntityId,
    this.blindsEntityId,
    this.lightEntityIds = const {},
  });

  factory HomeAssistantOptions.fromEnv() => HomeAssistantOptions(
    baseUrl: const String.fromEnvironment('HA_URL', defaultValue: ''),
    token: const String.fromEnvironment('HA_TOKEN', defaultValue: ''),
    livingAcEntityId: const String.fromEnvironment('HA_AC_ENTITY', defaultValue: 'climate.eeokeon'),
    bedroomAcEntityId: const String.fromEnvironment('HA_BEDROOM_AC_ENTITY', defaultValue: 'climate.eeokeon_anbang'),
    healthSensorPrefix: const String.fromEnvironment('HA_PHONE_PREFIX', defaultValue: 'sensor.sm_s931n_'),

    // ✅ [수정] 스크린샷 기반 실제 센서 ID 매핑
    airTempEntityId: const String.fromEnvironment('HA_AIR_TEMP', defaultValue: 'sensor.eeomoniteo_peulreoseu_temperature'),
    airHumEntityId: const String.fromEnvironment('HA_AIR_HUM', defaultValue: 'sensor.eeomoniteo_peulreoseu_humidity'),
    airCo2EntityId: const String.fromEnvironment('HA_AIR_CO2', defaultValue: 'sensor.eeomoniteo_peulreoseu_carbon_dioxide'),
    airPm1EntityId: const String.fromEnvironment('HA_AIR_PM1', defaultValue: 'sensor.eeomoniteo_peulreoseu_pm1'),
    airPm25EntityId: const String.fromEnvironment('HA_AIR_PM25', defaultValue: 'sensor.eeomoniteo_peulreoseu_pm2_5'),
    airPm10EntityId: const String.fromEnvironment('HA_AIR_PM10', defaultValue: 'sensor.eeomoniteo_peulreoseu_pm10'),
    airOdorEntityId: const String.fromEnvironment('HA_AIR_ODOR', defaultValue: 'sensor.eeomoniteo_peulreoseu_odor_sensor'), // 냄새
    airQualityEntityId: const String.fromEnvironment('HA_AIR_QUAL', defaultValue: 'sensor.eeomoniteo_peulreoseu_air_quality'), // 통합대기질

    hrvEntityId: const String.fromEnvironment('HA_HRV_ENTITY', defaultValue: ''),
    blindsEntityId: const String.fromEnvironment('HA_BLINDS_ENTITY', defaultValue: ''),
    lightEntityIds: {
      '거실': const String.fromEnvironment('HA_LIGHT_LIVING', defaultValue: ''),
      '침실': const String.fromEnvironment('HA_LIGHT_BEDROOM', defaultValue: ''),
      '주방': const String.fromEnvironment('HA_LIGHT_KITCHEN', defaultValue: ''),
    },
  );
}