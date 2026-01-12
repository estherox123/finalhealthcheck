// lib/data/iot/models.dart

import 'package:flutter/foundation.dart';

// -------------------- Enums --------------------

enum AcLocation { living, bedroom }

enum AcMode { cool, heat, fan, dry, auto }

extension AcModeLabel on AcMode {
  String get label => switch (this) {
    AcMode.cool => '냉방',
    AcMode.heat => '난방',
    AcMode.fan => '송풍',
    AcMode.dry => '제습',
    AcMode.auto => '자동',
  };
}

enum AcFanSpeed { auto, low, medium, high }

enum BlindsStatus { open, stop, close }

extension BlindsStatusLabel on BlindsStatus {
  String get label => switch (this) {
    BlindsStatus.open => '열림',
    BlindsStatus.stop => '정지',
    BlindsStatus.close => '닫힘'
  };
}

enum BrightnessLevel { dim, normal, bright }

extension BrightnessLabel on BrightnessLevel {
  String get label => switch (this) {
    BrightnessLevel.dim => '어둡게',
    BrightnessLevel.normal => '보통',
    BrightnessLevel.bright => '밝게'
  };
}

// -------------------- State Models --------------------

class AirconState {
  final bool isOn;
  final int temperature;
  final double currentTemperature;
  final double currentHumidity;
  final AcMode mode;
  final int timerHours;
  final AcFanSpeed fanSpeed;
  final bool isSwing;
  final bool isAutoMode;

  const AirconState({
    required this.isOn,
    required this.temperature,
    this.currentTemperature = 0.0,
    this.currentHumidity = 0.0,
    required this.mode,
    required this.timerHours,
    this.fanSpeed = AcFanSpeed.auto,
    this.isSwing = false,
    this.isAutoMode = false,
  });

  static const initial = AirconState(
    isOn: false,
    temperature: 24,
    currentTemperature: 24.0,
    currentHumidity: 50.0,
    mode: AcMode.cool,
    timerHours: 0,
    fanSpeed: AcFanSpeed.auto,
    isSwing: false,
    isAutoMode: false,
  );

  AirconState copyWith({
    bool? isOn,
    int? temperature,
    double? currentTemperature,
    double? currentHumidity,
    AcMode? mode,
    int? timerHours,
    AcFanSpeed? fanSpeed,
    bool? isSwing,
    bool? isAutoMode,
  }) {
    return AirconState(
      isOn: isOn ?? this.isOn,
      temperature: temperature ?? this.temperature,
      currentTemperature: currentTemperature ?? this.currentTemperature,
      currentHumidity: currentHumidity ?? this.currentHumidity,
      mode: mode ?? this.mode,
      timerHours: timerHours ?? this.timerHours,
      fanSpeed: fanSpeed ?? this.fanSpeed,
      isSwing: isSwing ?? this.isSwing,
      isAutoMode: isAutoMode ?? this.isAutoMode,
    );
  }
}

@immutable
class AdminSettings {
  final String seasonMode;
  final double summerTriggerTemp;
  final double summerTargetTemp;
  final double winterTriggerTemp;
  final double winterTargetTemp;
  final double humidityTrigger;
  final double humidityTarget;

  const AdminSettings({
    required this.seasonMode,
    required this.summerTriggerTemp,
    required this.summerTargetTemp,
    required this.winterTriggerTemp,
    required this.winterTargetTemp,
    required this.humidityTrigger,
    required this.humidityTarget,
  });

  static const initial = AdminSettings(
    seasonMode: 'Auto (사계절 감지)',
    summerTriggerTemp: 26.5,
    summerTargetTemp: 24.5,
    winterTriggerTemp: 19.0,
    winterTargetTemp: 22.0,
    humidityTrigger: 65.0,
    humidityTarget: 50.0,
  );

  AdminSettings copyWith({
    String? seasonMode,
    double? summerTriggerTemp,
    double? summerTargetTemp,
    double? winterTriggerTemp,
    double? winterTargetTemp,
    double? humidityTrigger,
    double? humidityTarget,
  }) {
    return AdminSettings(
      seasonMode: seasonMode ?? this.seasonMode,
      summerTriggerTemp: summerTriggerTemp ?? this.summerTriggerTemp,
      summerTargetTemp: summerTargetTemp ?? this.summerTargetTemp,
      winterTriggerTemp: winterTriggerTemp ?? this.winterTriggerTemp,
      winterTargetTemp: winterTargetTemp ?? this.winterTargetTemp,
      humidityTrigger: humidityTrigger ?? this.humidityTrigger,
      humidityTarget: humidityTarget ?? this.humidityTarget,
    );
  }
}

@immutable
class HrvState {
  final bool isOn;
  const HrvState({required this.isOn});
  HrvState copyWith({bool? isOn}) => HrvState(isOn: isOn ?? this.isOn);
  static const initial = HrvState(isOn: false);
}

@immutable
class LightRoomState {
  final bool isOn;
  final BrightnessLevel brightness;
  const LightRoomState({required this.isOn, required this.brightness});
  LightRoomState copyWith({bool? isOn, BrightnessLevel? brightness}) =>
      LightRoomState(isOn: isOn ?? this.isOn, brightness: brightness ?? this.brightness);
  static const off = LightRoomState(isOn: false, brightness: BrightnessLevel.normal);
}

typedef LightsState = Map<String, LightRoomState>;

// -------------------- Main Snapshot --------------------

@immutable
class IotSnapshot {
  // Device States
  final AirconState livingAc;
  final AirconState bedroomAc;
  final HrvState hrv;
  final BlindsStatus blinds;
  final LightsState lights;
  final AdminSettings adminSettings;

  // Health Data
  final double inbodyWeight;
  final double inbodyMuscle;
  final double inbodyFat;
  final double inbodyBMI;
  final double inbodyPBF;
  final double inbodyBMR;
  final double inbodyVFL;
  final double bpSystolic;
  final double bpDiastolic;
  final double bpPulse;

  // Air Quality Data (8종)
  final int co2;
  final double pm1;
  final double pm25;
  final double pm10;
  final int odor;
  final int airQuality;

  const IotSnapshot({
    required this.livingAc,
    required this.bedroomAc,
    required this.hrv,
    required this.blinds,
    required this.lights,
    required this.adminSettings,
    this.inbodyWeight = 0.0,
    this.inbodyMuscle = 0.0,
    this.inbodyFat = 0.0,
    this.inbodyBMI = 0.0,
    this.inbodyPBF = 0.0,
    this.inbodyBMR = 0.0,
    this.inbodyVFL = 0.0,
    this.bpSystolic = 0.0,
    this.bpDiastolic = 0.0,
    this.bpPulse = 0.0,
    // 초기값 0
    this.co2 = 0,
    this.pm1 = 0.0,
    this.pm25 = 0.0,
    this.pm10 = 0.0,
    this.odor = 0,
    this.airQuality = 0,
  });

  IotSnapshot copyWith({
    AirconState? livingAc,
    AirconState? bedroomAc,
    HrvState? hrv,
    BlindsStatus? blinds,
    LightsState? lights,
    AdminSettings? adminSettings,
    double? inbodyWeight,
    double? inbodyMuscle,
    double? inbodyFat,
    double? inbodyBMI,
    double? inbodyPBF,
    double? inbodyBMR,
    double? inbodyVFL,
    double? bpSystolic,
    double? bpDiastolic,
    double? bpPulse,
    int? co2,
    double? pm1,
    double? pm25,
    double? pm10,
    int? odor,
    int? airQuality,
  }) =>
      IotSnapshot(
        livingAc: livingAc ?? this.livingAc,
        bedroomAc: bedroomAc ?? this.bedroomAc,
        hrv: hrv ?? this.hrv,
        blinds: blinds ?? this.blinds,
        lights: lights ?? this.lights,
        adminSettings: adminSettings ?? this.adminSettings,
        inbodyWeight: inbodyWeight ?? this.inbodyWeight,
        inbodyMuscle: inbodyMuscle ?? this.inbodyMuscle,
        inbodyFat: inbodyFat ?? this.inbodyFat,
        inbodyBMI: inbodyBMI ?? this.inbodyBMI,
        inbodyPBF: inbodyPBF ?? this.inbodyPBF,
        inbodyBMR: inbodyBMR ?? this.inbodyBMR,
        inbodyVFL: inbodyVFL ?? this.inbodyVFL,
        bpSystolic: bpSystolic ?? this.bpSystolic,
        bpDiastolic: bpDiastolic ?? this.bpDiastolic,
        bpPulse: bpPulse ?? this.bpPulse,
        co2: co2 ?? this.co2,
        pm1: pm1 ?? this.pm1,
        pm25: pm25 ?? this.pm25,
        pm10: pm10 ?? this.pm10,
        odor: odor ?? this.odor,
        airQuality: airQuality ?? this.airQuality,
      );

  static IotSnapshot initial() => IotSnapshot(
    livingAc: AirconState.initial,
    bedroomAc: AirconState.initial,
    hrv: HrvState.initial,
    blinds: BlindsStatus.stop,
    lights: <String, LightRoomState>{
      '거실': LightRoomState.off,
      '침실': LightRoomState.off,
      '주방': LightRoomState.off
    },
    adminSettings: AdminSettings.initial,
  );
}