// lib/data/health_data_service.dart
import 'dart:async';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:health/health.dart';

/// 권장 읽기 타입(원하는 대로 수정 가능)
const kRecommendedTypes = <HealthDataType>[
  HealthDataType.STEPS,
  HealthDataType.SLEEP_SESSION,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.HEART_RATE,
  HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
];

class HealthDataService {
  final Health _health = Health();

  // ---------------------------------------------------------------------------
  // 권한 헬퍼
  // ---------------------------------------------------------------------------

  /// hasPermissions → requestAuthorization (READ 전용)
  Future<bool> ensureAuthorized(List<HealthDataType> types) async {
    final perms =
    List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);

    bool ok = await _health.hasPermissions(types, permissions: perms) ?? false;
    if (!ok) {
      ok = await _health.requestAuthorization(types, permissions: perms);
    }
    return ok;
  }

  /// 권한 요청 시트가 안 뜨거나, 거절 등으로 실패한 경우 Health Connect 설정/스토어로 보냄
  Future<bool> requestOrOpenSettings(List<HealthDataType> types) async {
    final ok = await ensureAuthorized(types);
    if (ok) return true;

    await openHealthConnectSettings();
    return false;
  }

  /// Health Connect 설정 열기 → 앱 정보 → 플레이스토어 순 폴백
  Future<void> openHealthConnectSettings() async {
    if (!Platform.isAndroid) return;

    // 1) 권장 인텐트
    try {
      const intent = AndroidIntent(
        action: 'androidx.health.ACTION_HEALTH_CONNECT_SETTINGS',
      );
      await intent.launch();
      return;
    } catch (_) {}

    // 2) 앱 상세 설정
    const pkg = 'com.google.android.apps.healthdata';
    try {
      final appDetails = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$pkg',
      );
      await appDetails.launch();
      return;
    } catch (_) {}

    // 3) 플레이스토어
    final uri = Uri.parse('market://details?id=$pkg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------------------
  // 공통 변환/수집
  // ---------------------------------------------------------------------------

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue?.toDouble();
    try {
      final any = (v as dynamic).numericValue;
      if (any is num) return any.toDouble();
    } catch (_) {}
    return null;
  }

  Future<int?> getStepsInInterval(DateTime start, DateTime end) async {
    final ok = await ensureAuthorized(const [HealthDataType.STEPS]);
    if (!ok) return null;

    try {
      final total = await _health.getTotalStepsInInterval(start, end);
      if (total != null) return total;
    } catch (_) {}

    try {
      final pts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );
      double sum = 0;
      for (final p in pts) {
        final d = _toDouble(p.value);
        if (d != null) sum += d;
      }
      return sum.round();
    } catch (_) {
      return null;
    }
  }

  /// 윈도우 내 수면 총합 (ASLEEP 우선, 없으면 SESSION). 경계 클램핑 처리.
  Future<Duration?> getSleepTotalInWindow(
      DateTime winStart, DateTime winEnd) async {
    final ok = await ensureAuthorized(
        const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION]);
    if (!ok) return null;

    try {
      final pts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION],
        startTime: winStart,
        endTime: winEnd,
      );
      final asleep =
      pts.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
      final base = asleep.isNotEmpty
          ? asleep
          : pts.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();

      int minSum = 0;
      for (final p in base) {
        final a = p.dateFrom, b = p.dateTo;
        if (a == null || b == null) continue;
        final s = a.isAfter(winStart) ? a : winStart;
        final e = b.isBefore(winEnd) ? b : winEnd;
        final m = e.difference(s).inMinutes;
        if (m > 0) minSum += m;
      }
      if (minSum <= 0) return null;
      return Duration(minutes: minSum);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 공개 메서드 (앱에서 써먹기)
  // ---------------------------------------------------------------------------

  Future<int?> getTodaySteps() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return getStepsInInterval(start, end);
  }

  /// 어젯밤(전날 18:00 ~ 오늘 12:00)
  Future<Duration?> getLastNightSleepDuration() async {
    final today0 = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final winStart = today0.subtract(const Duration(hours: 6));
    final winEnd = today0.add(const Duration(hours: 12));
    return getSleepTotalInWindow(winStart, winEnd);
  }

  /// 최근 N일 평균 걸음 (기록 없는 날 분모 제외)
  Future<int?> getStepsAverageOverDays(int days) async {
    final today0 = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    int sum = 0, cnt = 0;
    for (int i = 0; i < days; i++) {
      final d0 = today0.subtract(Duration(days: i));
      final d1 = d0.add(const Duration(days: 1));
      final v = await getStepsInInterval(d0, d1);
      if (v != null) {
        sum += v;
        cnt += 1;
      }
    }
    if (cnt == 0) return null;
    return (sum / cnt).round();
  }

  /// 최근 N밤 평균 수면 (각 밤: anchor 자정 기준 -6h ~ +12h, 기록 없는 밤 제외)
  Future<Duration?> getSleepAverageOverNights(int nights) async {
    final today0 = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    int sumMin = 0, cnt = 0;
    for (int i = 0; i < nights; i++) {
      final anchor = today0.subtract(Duration(days: i));
      final s = anchor.subtract(const Duration(hours: 6));
      final e = anchor.add(const Duration(hours: 12));
      final d = await getSleepTotalInWindow(s, e);
      if (d != null && d.inMinutes > 0) {
        sumMin += d.inMinutes;
        cnt += 1;
      }
    }
    if (cnt == 0) return null;
    return Duration(minutes: (sumMin / cnt).round());
  }
}
