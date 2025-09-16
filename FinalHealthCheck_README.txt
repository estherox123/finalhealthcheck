# FinalHealthCheck — Minimal Health Connect demo (걸음수 + 수면)

이 저장소는 `FinalHealthCheck` 안드로이드 앱(Flutter) 예제입니다.  
목표: Health Connect에서 걸음(7일 합)과 수면(세션/단계)을 읽는 최소 기능 앱을 동료의 휴대폰에서도 실행할 수 있게 구성했습니다.

> 현재 기능
> - 걸음: 지난 7일 총합(정상 동작 확인)
> - 수면: 권한/데이터 수집은 구현되어 있으나 디바이스/소스에 따라 권한 처리 필요 (나중 작업)

---

## 목차
1. 요구사항(개발환경)
2. 사전 준비(휴대폰)
3. 소스에서 바로 실행하기 (개발자 대상)
4. APK 빌드 & 설치 (비개발자/간편 테스트)
5. Health Connect 관련 체크리스트 (권한/데이터)
6. 배포 전 체크리스트(깃커밋 관련)
7. 트러블슈팅 (자주 발생하는 문제와 해결)
8. 연락처 / 기여

---

## 1) 요구사항 (개발환경)
- OS: Windows/macOS/Linux
- Flutter SDK: 권장 `>=3.3.0`
- Android SDK (API 35 권장; 프로젝트는 `compileSdk = 35`로 설정되어 있음)
- Android Studio (또는 VS Code + Android SDK/toolchain)
- `adb` (Android Platform Tools)
- 연결할 테스트폰 (Android) — iOS는 Health Connect 미지원

필요한 Flutter 패키지:
- `health: ^13.1.4`
- `permission_handler: ^11.3.1`

설치 명령 예:
```bash
flutter doctor
flutter pub get
```

---

## 2) 사전 준비 (테스트용 휴대폰)
### A. 개발자 옵션 & USB 디버깅
1. 휴대폰 설정 > 디바이스 정보 > 빌드 번호 7번 탭 → 개발자 모드 활성화  
2. 설정 > 개발자 옵션 > `USB 디버깅` ON  
3. PC에 USB 연결 → `adb devices` 로 연결 확인

### B. Health Connect 앱
- Google Health Connect(Play Store) 설치
- Health Connect가 잠금화면(핀/패턴 등)을 요구하는 경우 잠금화면 활성화 필요

---

## 3) 소스에서 바로 실행하기
1. 저장소 클론 (또는 ZIP 압축 해제)
2. 의존성 설치:
   ```bash
   flutter clean
   flutter pub get
   ```
3. Android 디바이스 연결 확인:
   ```bash
   adb devices
   ```
4. 앱 실행:
   ```bash
   flutter run
   ```

앱 최초 실행 시 권한 팝업이 뜨면 **걸음/수면 읽기 권한 허용** 필수.

---

## 4) APK 빌드 & 설치
### 빌드
```bash
flutter build apk --debug
# 결과: build/app/outputs/flutter-apk/app-debug.apk
```

### 설치
```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

또는 APK 파일을 직접 휴대폰에 전송 후 설치. (알 수 없는 앱 허용 필요)

---

## 5) Health Connect 체크리스트
1. Health Connect → 앱 권한:  
   - FinalHealthCheck 앱 → Steps/Sleep 읽기(Read) 허용  
   - 소스 앱(Samsung Health/Google Fit) → Steps/Sleep 쓰기(Share) 허용
2. Health Connect → Data & devices → 최근 Steps 데이터가 실제로 있는지 확인
3. 잠금화면 비활성화 시 HC 동작 안 할 수 있음 → 필요시 잠금화면 켜기
4. 앱이 HC 목록에 안 뜨면:
   - `AndroidManifest.xml`에 HC 관련 intent/queries 포함 여부 확인
   - 앱 삭제 후 재설치

---

## 6) 배포 전 체크리스트
- 포함:
  - `lib/main.dart`, `lib/health_controller.dart`
  - `pubspec.yaml`
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/build.gradle.kts`
- 제외:
  - Keystore (`.jks`)
  - `build/`, `.gradle/`, `.dart_tool/`, `local.properties`

추천 `.gitignore`:
```
/.dart_tool/
/.idea/
/.gradle/
/build/
/android/.gradle/
/android/local.properties
*.iml
*.keystore
```

---

## 7) 트러블슈팅

### A: 권한 팝업은 뜨는데 `미허용` 상태
- 원인: `configure()` 이전에 `requestAuthorization()` 호출
- 해결: `ensureConfigured()` 후 `hasPermissions()` 재확인

### B: HC에 앱이 안 뜸
- 원인: Manifest intent/alias 누락
- 해결: HC 관련 intent/alias 추가 후 앱 삭제·재설치

### C: 걸음수 0
- 원인: HC에 Steps 데이터 없음
- 해결: 소스 앱에서 HC 공유 허용 + 실제 걸음 데이터 동기화

로그 확인:
```bash
adb logcat | grep FLUTTER_HEALTH
```

---
