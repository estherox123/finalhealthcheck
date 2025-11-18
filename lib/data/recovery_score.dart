// lib/data/recovery_score.dart
//
// 워치 기반 "회복 지표" v0.1
// - 이동 중앙값 기준선 + 오늘 대비 편차 → 0–100 점수.
// - 기준선 window는 고정 3일이 아니라, 데이터가 쌓일수록 점진적으로 늘어남.
//   * minWindow(기본 3) ~ maxWindow(기본 7) 사이에서, 이전 기록 개수에 맞춰 자동 조정.
// Flutter 의존성 없음 (pure Dart).

import 'package:meta/meta.dart';

@immutable
class NightRecoveryRaw {
  final DateTime nightDate; // 기상 날짜 기준 (local)

  final double? hrMean;          // bpm (야간 평균)
  final double? hrvRmssd;        // ms (야간 평균)
  final double? respRate;        // breaths/min (야간 평균)
  final Duration? sleepTotal;    // 총 수면 시간
  final int? sleepAwakenings;    // 중간 각성 횟수 (없으면 null)
  final double? spo2Min;         // 야간 최소 SpO₂ (%), 없으면 null

  const NightRecoveryRaw({
    required this.nightDate,
    this.hrMean,
    this.hrvRmssd,
    this.respRate,
    this.sleepTotal,
    this.sleepAwakenings,
    this.spo2Min,
  });
}

@immutable
class NightRecoveryBaseline {
  final DateTime nightDate;

  final double? hrMeanBase;
  final double? hrvRmssdBase;
  final double? respRateBase;
  final Duration? sleepTotalBase;
  final int? sleepAwakeningsBase;
  final double? spo2MinBase;

  const NightRecoveryBaseline({
    required this.nightDate,
    this.hrMeanBase,
    this.hrvRmssdBase,
    this.respRateBase,
    this.sleepTotalBase,
    this.sleepAwakeningsBase,
    this.spo2MinBase,
  });
}

enum RecoveryLabel { recoveryUp, good, caution, needRest }

@immutable
class RecoveryScore {
  final DateTime nightDate;
  final int score; // 0–100
  final RecoveryLabel label;

  /// -1..1 사이 편차 값 (지표별 기여도 디버깅용)
  final Map<String, double> metricContributions;

  /// 사용된 지표/기준선 풀이 충분히 넓지 않을 때 true
  final bool lowConfidence;

  const RecoveryScore({
    required this.nightDate,
    required this.score,
    required this.label,
    required this.metricContributions,
    required this.lowConfidence,
  });
}

/// ---- 공통 중앙값 헬퍼 ----

double? _medianNum(List<double?> values) {
  final filtered = values.whereType<double>().toList();
  if (filtered.isEmpty) return null;
  filtered.sort();
  final m = filtered.length ~/ 2;
  if (filtered.length.isOdd) return filtered[m];
  return (filtered[m - 1] + filtered[m]) / 2.0;
}

Duration? _medianDuration(List<Duration?> values) {
  final mins = values
      .whereType<Duration>()
      .map((d) => d.inMinutes.toDouble())
      .toList();
  if (mins.isEmpty) return null;
  mins.sort();
  final m = mins.length ~/ 2;
  final double medianMinutes;
  if (mins.length.isOdd) {
    medianMinutes = mins[m];
  } else {
    medianMinutes = (mins[m - 1] + mins[m]) / 2.0;
  }
  return Duration(minutes: medianMinutes.round());
}

/// ---- 기준선 계산 (동적 window: minWindow ~ maxWindow) ----
///
/// nights는 아무 순서나 들어올 수 있고, 내부에서 날짜 오름차순으로 정렬.
/// i번째 밤에 대해:
///   - 이전 historyLen = i 개의 밤이 있으면
///   - window 크기 w는:
///       * historyLen == 0  → w = 0 (기준선 없음 → 전부 null)
///       * 1~(minWindow-1) → w = historyLen (있는 만큼)
///       * minWindow~maxWindow → w = historyLen (점점 증가)
///       * historyLen > maxWindow → w = maxWindow (최근 maxWindow박만 사용)
///
/// 기본값: minWindow=3, maxWindow=7 이면
///   - 1박: 1, 2박: 2, 3박: 3, 4박: 4, 5박: 5, 6박: 6, 7박 이상: 항상 7박 기준선.
List<NightRecoveryBaseline> computeNightBaselines(
    List<NightRecoveryRaw> nights, {
      int minWindow = 3,
      int maxWindow = 7,
    }) {
  if (nights.isEmpty) return const [];

  if (minWindow < 1) minWindow = 1;
  if (maxWindow < minWindow) maxWindow = minWindow;

  final sorted = [...nights]
    ..sort((a, b) => a.nightDate.compareTo(b.nightDate));

  int _effectiveWindow(int historyLen) {
    if (historyLen <= 0) return 0;

    // 원하는 window 크기: historyLen을 min~max 사이로 clamp
    final desired = historyLen.clamp(minWindow, maxWindow);
    // 단, 항상 historyLen을 넘으면 안 됨.
    final w = desired.clamp(1, historyLen);
    return w;
  }

  final result = <NightRecoveryBaseline>[];

  for (int i = 0; i < sorted.length; i++) {
    final historyLen = i; // i번째 밤 기준, 그 이전에 historyLen개의 밤이 있음
    final w = _effectiveWindow(historyLen);

    final List<NightRecoveryRaw> history;
    if (w <= 0) {
      history = const [];
    } else {
      final start = i - w;
      history = sorted.sublist(start, i); // 직전 w개만 사용
    }

    result.add(
      NightRecoveryBaseline(
        nightDate: sorted[i].nightDate,
        hrMeanBase: _medianNum(history.map((h) => h.hrMean).toList()),
        hrvRmssdBase: _medianNum(history.map((h) => h.hrvRmssd).toList()),
        respRateBase: _medianNum(history.map((h) => h.respRate).toList()),
        sleepTotalBase:
        _medianDuration(history.map((h) => h.sleepTotal).toList()),
        sleepAwakeningsBase: _medianNum(
          history.map((h) => h.sleepAwakenings?.toDouble()).toList(),
        )?.round(),
        spo2MinBase: _medianNum(history.map((h) => h.spo2Min).toList()),
      ),
    );
  }

  return result;
}

/// ---- 점수화 로직 ----

double? _computeDeviationRatio({
  required double? today,
  required double? baseline,
  required bool higherIsBetter,
  double limitRatio = 0.15, // ±15% 변화를 -1..1에 매핑
}) {
  if (today == null || baseline == null || baseline == 0) return null;

  final diffRatio = (today - baseline) / baseline; // today가 크면 +, 작으면 -
  double raw;
  if (higherIsBetter) {
    raw = diffRatio;
  } else {
    raw = -diffRatio;
  }

  if (raw > limitRatio) raw = limitRatio;
  if (raw < -limitRatio) raw = -limitRatio;

  return raw / limitRatio; // -1..1
}

class _MetricDev {
  final String key;
  final double deviation; // -1..1
  final double weight;
  _MetricDev(this.key, this.deviation, this.weight);
}

RecoveryScore _computeRecoveryScoreInternal({
  required NightRecoveryRaw today,
  required NightRecoveryBaseline baseline,
}) {
  final metrics = <_MetricDev>[];

  void _addMetric({
    required String key,
    required double? todayVal,
    required double? baseVal,
    required bool higherIsBetter,
    required double weight,
    double limitRatio = 0.15, // <-- 기본 15%
  }) {
    final dev = _computeDeviationRatio(
      today: todayVal,
      baseline: baseVal,
      higherIsBetter: higherIsBetter,
      limitRatio: limitRatio,
    );
    if (dev != null) {
      metrics.add(_MetricDev(key, dev, weight));
    }
  }

  // HR 평균 (낮을수록 좋음) — 그대로 15%
  _addMetric(
    key: 'hrMean',
    todayVal: today.hrMean,
    baseVal: baseline.hrMeanBase,
    higherIsBetter: false,
    weight: 0.25,
  );

  // HRV (RMSSD, 높을수록 좋음) — 지금은 사실상 null이지만, 향후 대비
  _addMetric(
    key: 'hrvRmssd',
    todayVal: today.hrvRmssd,
    baseVal: baseline.hrvRmssdBase,
    higherIsBetter: true,
    weight: 0.30,
  );

  // 수면 총량 (높을수록 좋음) — **limitRatio만 0.40으로 넓힘**
  if (today.sleepTotal != null && baseline.sleepTotalBase != null) {
    _addMetric(
      key: 'sleepTotal',
      todayVal: today.sleepTotal!.inMinutes.toDouble(),
      baseVal: baseline.sleepTotalBase!.inMinutes.toDouble(),
      higherIsBetter: true,
      weight: 0.20,
      limitRatio: 0.40, // ← 여기만 다름
    );
  }

  // 호흡수 (낮을수록 좋음)
  _addMetric(
    key: 'respRate',
    todayVal: today.respRate,
    baseVal: baseline.respRateBase,
    higherIsBetter: false,
    weight: 0.15,
  );

  // SpO₂ (있을 경우만, 높을수록 좋음)
  if (today.spo2Min != null || baseline.spo2MinBase != null) {
    _addMetric(
      key: 'spo2Min',
      todayVal: today.spo2Min,
      baseVal: baseline.spo2MinBase,
      higherIsBetter: true,
      weight: 0.10,
    );
  }

  if (metrics.isEmpty) {
    return RecoveryScore(
      nightDate: today.nightDate,
      score: 50,
      label: RecoveryLabel.caution,
      metricContributions: const {},
      lowConfidence: true,
    );
  }

  final weightSum =
  metrics.fold<double>(0.0, (sum, m) => sum + m.weight);

  final normalized = metrics.fold<double>(
    0.0,
        (sum, m) => sum + m.deviation * (m.weight / weightSum),
  ); // -1..1

  // ---- 점수 매핑 + 최소 20점 바닥 ----
  final rawScore = ((normalized + 1.0) / 2.0) * 100; // 0..100
  final floored = rawScore < 20.0 ? 20.0 : rawScore; // 최소 20
  final score = floored.clamp(0.0, 100.0).round();

  final label = () {
    if (score >= 70) return RecoveryLabel.recoveryUp;
    if (score >= 55) return RecoveryLabel.good;
    if (score >= 40) return RecoveryLabel.caution;
    return RecoveryLabel.needRest;
  }();

  final contributions = <String, double>{
    for (final m in metrics) m.key: m.deviation,
  };

  // NOTE:
  // - 아직도 lowConfidence는 "사용된 지표 weight 합"만 보고 판단한다.
  // - baseline window 길이(예: 아직 2박/3박뿐인 경우)를 추가로 반영하고 싶다면,
  //   computeRecoveryFromNights()에서 history 길이를 함께 넘겨서 조건을 추가하는 식으로 확장 가능.
  final lowConfidence = weightSum < 0.6;

  return RecoveryScore(
    nightDate: today.nightDate,
    score: score,
    label: label,
    metricContributions: contributions,
    lowConfidence: lowConfidence,
  );
}

/// 과거 N박(raw) → 오늘 기준 회복 점수.
/// nights는 날짜 오름차순(과거→현재)라고 가정.
RecoveryScore computeRecoveryFromNights(List<NightRecoveryRaw> nights) {
  if (nights.isEmpty) {
    return RecoveryScore(
      nightDate: DateTime.now(),
      score: 50,
      label: RecoveryLabel.caution,
      metricContributions: const {},
      lowConfidence: true,
    );
  }

  // 동적 window 기준선:
  // - minWindow=3: 최소 3박 이상부터 baseline이 조금 안정화
  // - maxWindow=7: 7박 이상부터는 항상 최근 7박만 사용 (너무 옛날은 버림)
  final baselines = computeNightBaselines(
    nights,
    minWindow: 3,
    maxWindow: 7,
  );

  final todayRaw = nights.last;
  final todayBaseline = baselines.last;

  return _computeRecoveryScoreInternal(
    today: todayRaw,
    baseline: todayBaseline,
  );
}
