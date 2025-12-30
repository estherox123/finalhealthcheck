// lib/data/iot/models.dart

import 'package:flutter/foundation.dart';

/// 에어컨 모드
enum AcMode { cool, heat, fan, dry, auto }

extension AcModeLabel on AcMode {
  String get label => switch (this) {
    AcMode.cool => '냉방',
    AcMode.heat => '난방',
    AcMode.fan  => '송풍',
    AcMode.dry  => '제습',
    AcMode.auto => '자동',
  };
}

enum AcFanSpeed { auto, low, medium, high }

/// 에어컨 상태
class AirconState {
  final bool isOn;
  final int temperature;        // 희망 온도
  final double currentTemperature;
  final double currentHumidity;
  final AcMode mode;
  final int timerHours;
  final AcFanSpeed fanSpeed;
  final bool isSwing;

  const AirconState({
    required this.isOn,
    required this.temperature,
    this.currentTemperature = 0.0,
    this.currentHumidity = 0.0,
    required this.mode,
    required this.timerHours,
    this.fanSpeed = AcFanSpeed.auto,
    this.isSwing = false,
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
    );
  }
}

/// HRV(환기) 상태
@immutable
class HrvState {
  final bool isOn;
  const HrvState({required this.isOn});

  HrvState copyWith({bool? isOn}) => HrvState(isOn: isOn ?? this.isOn);

  static const initial = HrvState(isOn: false);
}

/// 블라인드 상태
enum BlindsStatus { open, stop, close }
extension BlindsStatusLabel on BlindsStatus {
  String get label => switch (this) {
    BlindsStatus.open  => '열림',
    BlindsStatus.stop  => '정지',
    BlindsStatus.close => '닫힘',
  };
}

/// 조명 밝기
enum BrightnessLevel { dim, normal, bright }
extension BrightnessLabel on BrightnessLevel {
  String get label => switch (this) {
    BrightnessLevel.dim    => '어둡게',
    BrightnessLevel.normal => '보통',
    BrightnessLevel.bright => '밝게',
  };
}

/// 방별 조명 상태
@immutable
class LightRoomState {
  final bool isOn;
  final BrightnessLevel brightness;
  const LightRoomState({required this.isOn, required this.brightness});

  LightRoomState copyWith({bool? isOn, BrightnessLevel? brightness}) =>
      LightRoomState(
        isOn: isOn ?? this.isOn,
        brightness: brightness ?? this.brightness,
      );

  static const off = LightRoomState(isOn: false, brightness: BrightnessLevel.normal);
}

/// 전체 조명 묶음
typedef LightsState = Map<String, LightRoomState>;

/// 전체 IoT 대시보드 스냅샷
@immutable
class IotSnapshot {
  final AirconState aircon;
  final HrvState hrv;
  final BlindsStatus blinds;
  final LightsState lights;

  // 인바디 데이터 필드 (7종)
  final double inbodyWeight; // 체중 (kg)
  final double inbodyMuscle; // 골격근량 (kg)
  final double inbodyFat;    // 체지방량 (kg)
  final double inbodyBMI;    // BMI (kg/m²)
  final double inbodyPBF;    // 체지방률 (%)
  final double inbodyBMR;    // 기초대사량 (kcal)
  final double inbodyVFL;    // 내장지방레벨 (Lv)

  const IotSnapshot({
    required this.aircon,
    required this.hrv,
    required this.blinds,
    required this.lights,
    // 생성자 초기화
    this.inbodyWeight = 0.0,
    this.inbodyMuscle = 0.0,
    this.inbodyFat = 0.0,
    this.inbodyBMI = 0.0,
    this.inbodyPBF = 0.0,
    this.inbodyBMR = 0.0,
    this.inbodyVFL = 0.0,
  });

  IotSnapshot copyWith({
    AirconState? aircon,
    HrvState? hrv,
    BlindsStatus? blinds,
    LightsState? lights,
    // copyWith 파라미터
    double? inbodyWeight,
    double? inbodyMuscle,
    double? inbodyFat,
    double? inbodyBMI,
    double? inbodyPBF,
    double? inbodyBMR,
    double? inbodyVFL,
  }) =>
      IotSnapshot(
        aircon: aircon ?? this.aircon,
        hrv: hrv ?? this.hrv,
        blinds: blinds ?? this.blinds,
        lights: lights ?? this.lights,
        // 값 할당
        inbodyWeight: inbodyWeight ?? this.inbodyWeight,
        inbodyMuscle: inbodyMuscle ?? this.inbodyMuscle,
        inbodyFat: inbodyFat ?? this.inbodyFat,
        inbodyBMI: inbodyBMI ?? this.inbodyBMI,
        inbodyPBF: inbodyPBF ?? this.inbodyPBF,
        inbodyBMR: inbodyBMR ?? this.inbodyBMR,
        inbodyVFL: inbodyVFL ?? this.inbodyVFL,
      );

  static IotSnapshot initial() => IotSnapshot(
    aircon: AirconState.initial,
    hrv: HrvState.initial,
    blinds: BlindsStatus.stop,
    lights: <String, LightRoomState>{
      '거실': LightRoomState.off,
      '침실': LightRoomState.off,
      '주방': LightRoomState.off,
    },
    // 숫자는 기본 0.0으로 자동 초기화
  );
}