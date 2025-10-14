// lib/data/iot/models.dart
import 'package:flutter/foundation.dart';

/// 에어컨 모드
enum AcMode { cool, heat, fan }

extension AcModeLabel on AcMode {
  String get label => switch (this) {
    AcMode.cool => '냉방',
    AcMode.heat => '난방',
    AcMode.fan  => '송풍',
  };
}

/// 에어컨 상태
@immutable
class AirconState {
  final bool isOn;
  final int temperature; // 16~30
  final AcMode mode;
  final int timerHours; // 0/1/2/4

  const AirconState({
    required this.isOn,
    required this.temperature,
    required this.mode,
    required this.timerHours,
  });

  AirconState copyWith({
    bool? isOn,
    int? temperature,
    AcMode? mode,
    int? timerHours,
  }) =>
      AirconState(
        isOn: isOn ?? this.isOn,
        temperature: temperature ?? this.temperature,
        mode: mode ?? this.mode,
        timerHours: timerHours ?? this.timerHours,
      );

  static const initial = AirconState(
    isOn: false,
    temperature: 24,
    mode: AcMode.cool,
    timerHours: 0,
  );
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

  const IotSnapshot({
    required this.aircon,
    required this.hrv,
    required this.blinds,
    required this.lights,
  });

  IotSnapshot copyWith({
    AirconState? aircon,
    HrvState? hrv,
    BlindsStatus? blinds,
    LightsState? lights,
  }) =>
      IotSnapshot(
        aircon: aircon ?? this.aircon,
        hrv: hrv ?? this.hrv,
        blinds: blinds ?? this.blinds,
        lights: lights ?? this.lights,
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
  );
}
