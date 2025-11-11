// lib/data/iot/iot_api.dart
/// IoT 게이트웨이 API 추상 인터페이스
/// 스냅샷 조회 및 에어컨·HRV·블라인드·조명 제어 메서드 정의
/// 임시.

import 'models.dart';

/// 실제 클라우드/로컬 게이트웨이 API를 추상화
abstract class IotApi {
  Future<IotSnapshot> fetchSnapshot();

  // Aircon
  Future<AirconState> setAirconPower(bool on);
  Future<AirconState> setAirconTemp(int temp);
  Future<AirconState> setAirconMode(AcMode mode);
  Future<AirconState> setAirconTimer(int hours);

  // HRV
  Future<HrvState> setHrvPower(bool on);

  // Blinds
  Future<BlindsStatus> controlBlinds(BlindsStatus status);

  // Lights
  Future<LightsState> toggleLight(String room);
  Future<LightsState> setBrightness(String room, BrightnessLevel b);
}
