// lib/data/health_repository.dart
/// Health 데이터 리포지토리
/// 대시보드 스냅샷(수면점수/HR/HRV/호흡수·7일 대비 추세) 계산과 걸음수 합계/일별 집계를 제공

import 'dart:math';
import 'package:health/health.dart';

class StepsDay {
  final DateTime date; // 로컬 자정 기준 날짜(연-월-일만 사용)
  final int steps;
  const StepsDay(this.date, this.steps);
}

/// 대시보드에서 쓰는 요약 스냅샷
class DashboardSnapshot {
  final int? sleepScore;            // 0~100 (수면시간 기반 간이 점수)
  final int? heartRateAvg;          // bpm
  final int? hrvRmssd;              // ms
  final double? respirationNight;   // rpm
  /// 7일 평균 대비 변화: +1(상승) / 0(유지) / -1(하락)
  final Map<String, int> deltaVs7d;

  const DashboardSnapshot({
    required this.sleepScore,
    required this.heartRateAvg,
    required this.hrvRmssd,
    required this.respirationNight,
    required this.deltaVs7d,
  });
}

abstract class HealthRepository {
  Future<bool> ensurePermissions();
  Future<DashboardSnapshot> readDashboard({required DateTime now});

  // ✅ 여기(인터페이스)에 선언
  Future<int?> readStepsSum(DateTime from, DateTime to);
  Future<List<StepsDay>> readStepsDaily({
    required DateTime start, // 포함
    required DateTime end,   // 제외(자정 경계 권장)
  });
}

class HealthRepositoryImpl implements HealthRepository {
  final Health _health = Health();

  /// 사용할 타입들 (기기/앱에 따라 일부는 미지원일 수 있음)
  static const List<HealthDataType> _maybeTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
  ];

  List<HealthDataAccess> get _reads =>
      _maybeTypes.map((_) => HealthDataAccess.READ).toList();

  @override
  Future<bool> ensurePermissions() async {
    // permission launcher 등록 (없으면 "Permission launcher not found")
    await _health.configure();

    final has = await _health.hasPermissions(_maybeTypes, permissions: _reads) ?? false;
    if (has) return true;

    final ok = await _health.requestAuthorization(_maybeTypes, permissions: _reads);
    return ok;
  }

  @override
  Future<DashboardSnapshot> readDashboard({required DateTime now}) async {
    // 시간 경계 (현지 자정 기준)
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final sevenDaysAgo = startOfToday.subtract(const Duration(days: 7));

    // ---- 1) 어제 수면 세션 총합(분) → 8시간 = 100점으로 환산
    final int? sleepMinutes = await _sumSleepMinutes(startOfYesterday, startOfToday);
    final int? sleepScore = (sleepMinutes == null)
        ? null
        : max(0, min(100, ((sleepMinutes / 480.0) * 100).round()));

    // ---- 2) 어제 평균들 (자정~자정)
    final double? hrAvgYesterday = await _avgNum(
        HealthDataType.HEART_RATE, startOfYesterday, startOfToday);
    final double? hrvRmssdYesterday = await _avgNum(
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD, startOfYesterday, startOfToday);
    final double? respYesterday = await _avgNum(
        HealthDataType.RESPIRATORY_RATE, startOfYesterday, startOfToday);

    // ---- 3) 7일 평균(베이스라인)
    final double? hrAvg7d = await _avgNum(
        HealthDataType.HEART_RATE, sevenDaysAgo, startOfToday);
    final double? hrvAvg7d = await _avgNum(
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD, sevenDaysAgo, startOfToday);
    final double? respAvg7d = await _avgNum(
        HealthDataType.RESPIRATORY_RATE, sevenDaysAgo, startOfToday);

    // ---- 4) 델타 계산
    final Map<String, int> delta = {
      'sleep': 0, // MVP: 내부 계산값이라 베이스라인 없이 0
      'hr'   : _deltaByRatio(hrAvgYesterday, hrAvg7d, higherIsBetter: false),
      'hrv'  : _deltaByRatio(hrvRmssdYesterday, hrvAvg7d, higherIsBetter: true),
      'resp' : _deltaByRatio(respYesterday, respAvg7d, higherIsBetter: false),
    };

    return DashboardSnapshot(
      sleepScore: sleepScore,
      heartRateAvg: hrAvgYesterday?.round(),      // double → int
      hrvRmssd: hrvRmssdYesterday?.round(),       // double → int
      respirationNight: respYesterday,            // 호흡수는 소수 허용
      deltaVs7d: delta,
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ 여기(클래스 레벨)에 'readStepsSum / readStepsDaily'를 둬야 함
  // ---------------------------------------------------------------------------

  @override
  Future<int?> readStepsSum(DateTime from, DateTime to) async {
    try {
      final pts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: from,
        endTime: to,
      );
      double sum = 0;
      for (final p in pts) {
        final v = _asDouble(p.value);
        if (v != null) sum += v;
      }
      return sum.round();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<StepsDay>> readStepsDaily({
    required DateTime start,
    required DateTime end,
  }) async {
    // 로컬 자정 경계 보정
    DateTime _day0(DateTime d) => DateTime(d.year, d.month, d.day);

    try {
      final pts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );

      // 날짜별 합계
      final Map<DateTime, double> acc = {};
      for (final p in pts) {
        // steps는 구간/샘플 모두 가능 → dateFrom 우선
        final d = p.dateFrom ?? p.dateTo ?? start;
        final key = _day0(d.toLocal());
        final v = _asDouble(p.value) ?? 0.0;
        acc.update(key, (x) => x + v, ifAbsent: () => v);
      }

      // 빈 날짜도 0으로 채우기
      final List<StepsDay> out = [];
      for (DateTime d = _day0(start);
      d.isBefore(end);
      d = d.add(const Duration(days: 1))) {
        final v = acc[_day0(d)] ?? 0.0;
        out.add(StepsDay(_day0(d), v.round()));
      }
      return out;
    } catch (_) {
      // 실패 시에도 차트 틀이 깨지지 않도록 0으로 채운 리스트 리턴
      final List<StepsDay> out = [];
      for (DateTime d = DateTime(start.year, start.month, start.day);
      d.isBefore(end);
      d = d.add(const Duration(days: 1))) {
        out.add(StepsDay(DateTime(d.year, d.month, d.day), 0));
      }
      return out;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// HealthValue → double 로 안전 추출
  double? _asDouble(dynamic v) {
    if (v == null) return null;

    // 구버전/특정 타입에서 value가 그냥 num 인 경우
    if (v is num) return v.toDouble();

    // v13+: HealthValue 래퍼 계열 (숫자형은 공통으로 NumericHealthValue 상속)
    if (v is NumericHealthValue) {
      final n = v.numericValue; // num?
      return n == null ? null : n.toDouble();
    }

    // 필요하면 추가 분기(CaloriesHealthValue 등)도 여기서 처리 가능
    return null; // 숫자로 해석 불가
  }

  /// 어제 수면세션 총합(분)
  Future<int?> _sumSleepMinutes(DateTime from, DateTime to) async {
    try {
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_SESSION],
        startTime: from,
        endTime: to,
      );
      if (points.isEmpty) return null;

      int minutes = 0;
      for (final p in points) {
        final a = p.dateFrom, b = p.dateTo;
        if (a != null && b != null) {
          minutes += b.difference(a).inMinutes;
        }
      }
      return minutes > 0 ? minutes : null;
    } catch (_) {
      return null;
    }
  }

  /// 주어진 타입의 평균값(double). 없거나 미지원이면 null.
  Future<double?> _avgNum(HealthDataType t, DateTime from, DateTime to) async {
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [t],
        startTime: from,
        endTime: to,
      );
      if (points.isEmpty) return null;

      double sum = 0;
      int n = 0;
      for (final p in points) {
        final d = _asDouble(p.value);
        if (d != null) {
          sum += d;
          n++;
        }
      }
      return n > 0 ? (sum / n) : null;
    } catch (_) {
      return null;
    }
  }

  /// 7일 평균 대비 변화: ±3% 임계 (higherIsBetter에 따라 방향성 반영)
  int _deltaByRatio(double? today, double? avg7d, {required bool higherIsBetter}) {
    if (today == null || avg7d == null || avg7d == 0) return 0;
    final ratio = today / avg7d;
    if (higherIsBetter) {
      if (ratio >= 1.03) return 1;
      if (ratio <= 0.97) return -1;
      return 0;
    } else {
      if (ratio <= 0.97) return 1;   // 낮을수록 좋음
      if (ratio >= 1.03) return -1;  // 높을수록 나쁨
      return 0;
    }
  }
}
