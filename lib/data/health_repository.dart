// lib/data/health_repository.dart
/// Health 데이터 리포지토리
/// 대시보드 스냅샷(수면점수/HR/HRV/호흡수·7일 대비 추세) 계산과
/// 걸음수 합계/일별 집계를 제공

import 'dart:math';
import 'package:health/health.dart';

class StepsDay {
  final DateTime date; // 로컬 자정 기준 날짜(연-월-일만 사용)
  final int steps;
  const StepsDay(this.date, this.steps);
}

/// 대시보드에서 쓰는 요약 스냅샷
class DashboardSnapshot {
  /// 지난 밤 수면 점수 0~100
  final int? sleepScore;
  final int? heartRateAvg;        // bpm
  final int? hrvRmssd;            // ms
  final double? respirationNight; // rpm

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

  Future<int?> readStepsSum(DateTime from, DateTime to);

  Future<List<StepsDay>> readStepsDaily({
    required DateTime start, // 포함
    required DateTime end, // 제외(자정 경계 권장)
  });
}

class HealthRepositoryImpl implements HealthRepository {
  final Health _health = Health();

  /// 사용할 타입들 (기기/앱에 따라 일부는 미지원일 수 있음)
  static const List<HealthDataType> _maybeTypes = [
    // 수면
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    // 심혈관/호흡
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
    // 활동(걸음수)
    HealthDataType.STEPS,
  ];

  List<HealthDataAccess> get _reads =>
      _maybeTypes.map((_) => HealthDataAccess.READ).toList();

  @override
  Future<bool> ensurePermissions() async {
    // permission launcher 등록 (없으면 "Permission launcher not found")
    await _health.configure();

    final has =
        await _health.hasPermissions(_maybeTypes, permissions: _reads) ??
            false;
    if (has) return true;

    final ok =
    await _health.requestAuthorization(_maybeTypes, permissions: _reads);
    return ok;
  }

  @override
  Future<DashboardSnapshot> readDashboard({required DateTime now}) async {
    // 시간 경계 (현지 자정 기준)
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final sevenDaysAgo = startOfToday.subtract(const Duration(days: 7));

    // "지난 밤" 윈도우: 어제 18:00 ~ 오늘 12:00 (수면/심박 상세 페이지와 동일 기준)
    final winAnchor = startOfToday;
    final winStart = winAnchor.subtract(const Duration(hours: 6));
    final winEnd   = winAnchor.add(const Duration(hours: 12));

    // ---- 1) 지난 밤 수면점수(고급) : 어제 18:00 ~ 오늘 12:00
    final int? sleepScore = await _computeSleepScoreAdvanced(now);

    // ---- 2) 어제 평균들 (자정~자정)
    // 심박수는 "지난 밤" 기준(어제 18:00 ~ 오늘 12:00)
    final double? hrAvgLastNight = await _avgNum(
      HealthDataType.HEART_RATE,
      winStart,
      winEnd,
    );
    final double? hrvRmssdYesterday = await _avgNum(
      HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      startOfYesterday,
      startOfToday,
    );
    final double? respYesterday = await _avgNum(
      HealthDataType.RESPIRATORY_RATE,
      startOfYesterday,
      startOfToday,
    );

    // ---- 3) 7일 평균(베이스라인)
    // (1) 심박수: "지난 7번의 밤" 평균 (각 밤의 평균을 다시 평균)
    //   - 기준 밤: 오늘 카드가 보여주는 "지난 밤"은 제외
    //   - 앵커: 오늘 자정 기준으로 1~7일 전까지
    double? hrAvg7Nights;
    {
      double sumOfNightAvgs = 0;
      int nightCount = 0;

      for (int i = 1; i <= 7; i++) {
        // i=1 → 어제 밤, i=7 → 7일 전 밤
        final anchor = startOfToday.subtract(Duration(days: i));
        final s = anchor.subtract(const Duration(hours: 6));  // 18:00
        final e = anchor.add(const Duration(hours: 12));      // 다음날 12:00

        final pts = await _health.getHealthDataFromTypes(
          types: const [HealthDataType.HEART_RATE],
          startTime: s,
          endTime: e,
        );

        double sum = 0;
        int n = 0;
        for (final p in pts) {
          final v = _asDouble(p.value);
          if (v == null) continue;
          sum += v;
          n++;
        }

        if (n > 0) {
          sumOfNightAvgs += (sum / n); // 그 밤의 평균
          nightCount++;
        }
      }

      if (nightCount > 0) {
        hrAvg7Nights = sumOfNightAvgs / nightCount;
      }
    }

// (2) HRV / 호흡수는 기존처럼 자정~자정 7일 평균 유지
    final double? hrvAvg7d = await _avgNum(
      HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      sevenDaysAgo,
      startOfToday,
    );
    final double? respAvg7d = await _avgNum(
      HealthDataType.RESPIRATORY_RATE,
      sevenDaysAgo,
      startOfToday,
    );

    // ---- 4) 델타 계산
    final Map<String, int> delta = {
      // 수면 점수는 일단 추세 0 (MVP)
      'sleep': 0,
      'hr': _deltaByRatio(
        hrAvgLastNight,
        hrAvg7Nights,
        higherIsBetter: false,
      ),
      'hrv': _deltaByRatio(
        hrvRmssdYesterday,
        hrvAvg7d,
        higherIsBetter: true,
      ),
      'resp': _deltaByRatio(
        respYesterday,
        respAvg7d,
        higherIsBetter: false,
      ),
    };

    return DashboardSnapshot(
      sleepScore: sleepScore,
      heartRateAvg: hrAvgLastNight?.round(),
      hrvRmssd: hrvRmssdYesterday?.round(),
      respirationNight: respYesterday,
      deltaVs7d: delta,
    );
  }

  // ---------------------------------------------------------------------------
  // 걸음수 관련
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
    DateTime _day0(DateTime d) => DateTime(d.year, d.month, d.day);

    try {
      final pts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );

      final Map<DateTime, double> acc = {};
      for (final p in pts) {
        final d = p.dateFrom ?? p.dateTo ?? start;
        final key = _day0(d.toLocal());
        final v = _asDouble(p.value) ?? 0.0;
        acc.update(key, (x) => x + v, ifAbsent: () => v);
      }

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
  // 수면 점수 계산 (고급 버전)
  // ---------------------------------------------------------------------------

  /// 지난 밤 수면 점수 (0~100)
  /// - 윈도우: 어제 18:00 ~ 오늘 12:00
  /// - 사용 데이터: 수면 단계(깊은/얕은/렘/깸) 기반
  /// - 단계 데이터가 없으면: 총 수면 시간 기반 간이 점수
  Future<int?> _computeSleepScoreAdvanced(DateTime now) async {
    final today0 = DateTime(now.year, now.month, now.day);
    final winStart = today0.subtract(const Duration(hours: 6));
    final winEnd = today0.add(const Duration(hours: 12));

    try {
      final stageTypes = <HealthDataType>[
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_AWAKE,
      ];

      final stagePoints = await _health.getHealthDataFromTypes(
        types: stageTypes,
        startTime: winStart,
        endTime: winEnd,
      );

      Duration deep = Duration.zero;
      Duration light = Duration.zero;
      Duration rem = Duration.zero;
      Duration wake = Duration.zero;

      for (final p in stagePoints) {
        final a = p.dateFrom;
        final b = p.dateTo;
        if (a == null || b == null) continue;

        final s = a.isBefore(winStart) ? winStart : a;
        final e = b.isAfter(winEnd) ? winEnd : b;
        if (!e.isAfter(s)) continue;

        final dur = e.difference(s);

        switch (p.type) {
          case HealthDataType.SLEEP_DEEP:
            deep += dur;
            break;
          case HealthDataType.SLEEP_LIGHT:
            light += dur;
            break;
          case HealthDataType.SLEEP_REM:
            rem += dur;
            break;
          case HealthDataType.SLEEP_AWAKE:
            wake += dur;
            break;
          default:
            break;
        }
      }

      final totalStage =
          deep + light + rem + wake; // 단계 데이터가 하나라도 있나 확인

      // 단계 데이터가 전혀 없는 경우 → 세션 기반 간이 점수로 폴백
      if (totalStage.inMinutes <= 0) {
        final mins = await _sumSleepMinutes(winStart, winEnd);
        if (mins == null) return null;
        return _sleepScoreDurationOnly(mins);
      }

      final totalSleep = deep + light + rem; // 실제 수면 시간
      if (totalSleep.inMinutes <= 0) {
        final mins = await _sumSleepMinutes(winStart, winEnd);
        if (mins == null) return null;
        return _sleepScoreDurationOnly(mins);
      }

      final totalInBed = totalSleep + wake;

      return _sleepScoreFromComponents(
        totalSleepMinutes: totalSleep.inMinutes,
        inBedMinutes: totalInBed.inMinutes,
        deepMinutes: deep.inMinutes,
        remMinutes: rem.inMinutes,
      );
    } catch (_) {
      // 오류 시에도 완전히 비우지 말고, 세션 기반 점수라도 시도
      final mins = await _sumSleepMinutes(winStart, winEnd);
      if (mins == null) return null;
      return _sleepScoreDurationOnly(mins);
    }
  }

  /// "총 수면 시간만" 가지고 계산하는 간이 점수 (0~100)
  int _sleepScoreDurationOnly(int sleepMinutes) {
    final ds = _durationComponentScore(sleepMinutes);
    return ds.round().clamp(0, 100);
  }

  /// 수면 시간/효율/단계 비율을 모두 사용한 점수 (0~100)
  int _sleepScoreFromComponents({
    required int totalSleepMinutes,
    required int inBedMinutes,
    required int deepMinutes,
    required int remMinutes,
  }) {
    final double durationScore = _durationComponentScore(totalSleepMinutes);

    double? efficiency;
    if (inBedMinutes > 0 && totalSleepMinutes > 0) {
      efficiency = totalSleepMinutes / inBedMinutes;
    }

    final double efficiencyScore = _efficiencyComponentScore(efficiency);

    double? deepRemRatio;
    if (totalSleepMinutes > 0) {
      deepRemRatio = (deepMinutes + remMinutes) / totalSleepMinutes;
    }

    final double stageScore = _stageComponentScore(deepRemRatio);

    // 가중치: 시간 50% + 효율 25% + 단계비율 25%
    final double overall =
        durationScore * 0.5 + efficiencyScore * 0.25 + stageScore * 0.25;

    return overall.round().clamp(0, 100);
  }

  /// 수면 시간 컴포넌트 (0~100)
  /// - 이상적인 목표: 8시간
  /// - 7~9시간에 가까우면 100점
  /// - 4시간 이하 / 12시간 이상은 0~20점 수준
  double _durationComponentScore(int minutes) {
    final h = minutes / 60.0;
    const ideal = 8.0;
    const fullRange = 1.0; // 7~9시간 → 100점
    const zeroRange = 4.0; // 4시간 이하 / 12시간 이상 부근부터 크게 감점

    final diff = (h - ideal).abs();

    if (diff <= fullRange) {
      return 100.0;
    }
    if (diff >= zeroRange) {
      return 20.0;
    }

    // diff: 1h → 100점, 4h → 20점 (선형)
    final t = (diff - fullRange) / (zeroRange - fullRange); // 0~1
    return 100.0 - t * 80.0;
  }

  /// 수면 효율 컴포넌트 (0~100)
  /// - 효율 = 실제 수면 / 침대 머문 시간
  /// - 90% 이상: 100점
  /// - 70~90%: 40~100점
  /// - 50~70%: 0~40점
  /// - 데이터 없으면 60점(중립)으로 처리
  double _efficiencyComponentScore(double? efficiency) {
    if (efficiency == null) return 60.0;

    double e = efficiency;
    if (e.isNaN || e.isInfinite) return 60.0;
    e = e.clamp(0.0, 1.0);

    if (e >= 0.9) return 100.0;
    if (e <= 0.5) return 0.0;
    if (e <= 0.7) {
      // 0.5 → 0점, 0.7 → 40점
      final t = (e - 0.5) / (0.7 - 0.5);
      return 0.0 + t * 40.0;
    }

    // 0.7~0.9 → 40~100
    final t = (e - 0.7) / (0.9 - 0.7);
    return 40.0 + t * 60.0;
  }

  /// 깊은+렘 수면 비율 컴포넌트 (0~100)
  /// - center: 45% 부근이 가장 이상적
  /// - 35~55% → 100점
  /// - center에서 30% 이상 벗어나면 40점까지 감점
  /// - 데이터 없으면 60점(중립)
  double _stageComponentScore(double? ratioDeepRem) {
    if (ratioDeepRem == null) return 60.0;

    double r = ratioDeepRem;
    if (r.isNaN || r.isInfinite) return 60.0;
    r = r.clamp(0.0, 1.0);

    const center = 0.45;
    const fullRange = 0.10; // ±10% → 100점
    const zeroRange = 0.30; // ±30% → 40점

    final diff = (r - center).abs();
    if (diff <= fullRange) return 100.0;
    if (diff >= zeroRange) return 40.0;

    final t = (diff - fullRange) / (zeroRange - fullRange); // 0~1
    return 100.0 - t * 60.0;
  }

  // ---------------------------------------------------------------------------
  // 공통 헬퍼들
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

    return null; // 숫자로 해석 불가
  }

  /// 주어진 구간의 수면세션 총합(분)
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
        final a = p.dateFrom;
        final b = p.dateTo;
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
  Future<double?> _avgNum(
      HealthDataType t,
      DateTime from,
      DateTime to,
      ) async {
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
  int _deltaByRatio(
      double? today,
      double? avg7d, {
        required bool higherIsBetter,
      }) {
    if (today == null || avg7d == null || avg7d == 0) return 0;
    final ratio = today / avg7d;
    if (higherIsBetter) {
      if (ratio >= 1.03) return 1;
      if (ratio <= 0.97) return -1;
      return 0;
    } else {
      if (ratio <= 0.97) return 1; // 낮을수록 좋음
      if (ratio >= 1.03) return -1; // 높을수록 나쁨
      return 0;
    }
  }
}
