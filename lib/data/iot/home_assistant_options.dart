/// Home Assistant 접속/엔티티 옵션.
/// 토큰·엔티티 ID를 코드에 직접 넣기보다 `--dart-define`로 주입하세요.
class HomeAssistantOptions {
  final String baseUrl; // 예: http://homeassistant.local:8123
  final String token; // Long-Lived Access Token
  final String acEntityId; // climate.xxx
  final String? hrvEntityId; // fan.xxx (선택)
  final String? blindsEntityId; // cover.xxx (선택)
  final Map<String, String> lightEntityIds; // room -> light.xxx

  const HomeAssistantOptions({
    required this.baseUrl,
    required this.token,
    required this.acEntityId,
    this.hrvEntityId,
    this.blindsEntityId,
    this.lightEntityIds = const {},
  });

  /// `flutter run --dart-define` 로 전달된 값을 사용.
  factory HomeAssistantOptions.fromEnv() => HomeAssistantOptions(
        baseUrl: const String.fromEnvironment('HA_URL', defaultValue: ''),
        token: const String.fromEnvironment('HA_TOKEN', defaultValue: ''),
        acEntityId:
            const String.fromEnvironment('HA_AC_ENTITY', defaultValue: ''),
        hrvEntityId:
            const String.fromEnvironment('HA_HRV_ENTITY', defaultValue: ''),
        blindsEntityId:
            const String.fromEnvironment('HA_BLINDS_ENTITY', defaultValue: ''),
        lightEntityIds: {
          // 기본 방 이름 매핑. 필요 시 dart-define 으로 덮어쓰기.
          '거실':
              const String.fromEnvironment('HA_LIGHT_LIVING', defaultValue: ''),
          '침실':
              const String.fromEnvironment('HA_LIGHT_BEDROOM', defaultValue: ''),
          '주방':
              const String.fromEnvironment('HA_LIGHT_KITCHEN', defaultValue: ''),
        },
      );

  bool get isConfigured =>
      baseUrl.isNotEmpty && token.isNotEmpty && acEntityId.isNotEmpty;
}

