// lib/data/recovery_score.dart
import 'package:meta/meta.dart';

@immutable
class NightRecoveryRaw {
  final DateTime nightDate;
  final double? hrMean;
  final double? hrvRmssd;
  final double? respRate;
  final Duration? sleepTotal;
  final int? sleepAwakenings;
  final double? spo2Min;

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
  final int score;
  final RecoveryLabel label;
  final Map<String, double> metricContributions;
  final bool lowConfidence;

  const RecoveryScore({
    required this.nightDate,
    required this.score,
    required this.label,
    required this.metricContributions,
    required this.lowConfidence,
  });
}

// ---------------- 헬퍼 함수 ----------------

double? _medianNum(List<double?> values) {
  final filtered = values.whereType<double>().toList();
  if (filtered.isEmpty) return null;
  filtered.sort();
  final m = filtered.length ~/ 2;
  if (filtered.length.isOdd) return filtered[m];
  return (filtered[m - 1] + filtered[m]) / 2.0;
}

Duration? _medianDuration(List<Duration?> values) {
  final mins = values.whereType<Duration>().map((d) => d.inMinutes.toDouble()).toList();
  if (mins.isEmpty) return null;
  mins.sort();
  final m = mins.length ~/ 2;
  return Duration(minutes: (mins.length.isOdd ? mins[m] : (mins[m - 1] + mins[m]) / 2.0).round());
}

List<NightRecoveryBaseline> computeNightBaselines(List<NightRecoveryRaw> nights, {int minWindow = 3, int maxWindow = 7}) {
  if (nights.isEmpty) return const [];
  final sorted = [...nights]..sort((a, b) => a.nightDate.compareTo(b.nightDate));
  final result = <NightRecoveryBaseline>[];

  for (int i = 0; i < sorted.length; i++) {
    final w = i.clamp(minWindow, maxWindow).clamp(0, i);
    final history = w <= 0 ? <NightRecoveryRaw>[] : sorted.sublist(i - w, i);

    result.add(NightRecoveryBaseline(
      nightDate: sorted[i].nightDate,
      hrMeanBase: _medianNum(history.map((h) => h.hrMean).toList()),
      hrvRmssdBase: _medianNum(history.map((h) => h.hrvRmssd).toList()),
      respRateBase: _medianNum(history.map((h) => h.respRate).toList()),
      sleepTotalBase: _medianDuration(history.map((h) => h.sleepTotal).toList()),
      sleepAwakeningsBase: _medianNum(history.map((h) => h.sleepAwakenings?.toDouble()).toList())?.round(),
      spo2MinBase: _medianNum(history.map((h) => h.spo2Min).toList()),
    ));
  }
  return result;
}

// ---------------- 점수화 로직 ----------------

double? _computeDeviationRatio({
  required double? today,
  required double? baseline,
  required bool higherIsBetter,
  double limitRatio = 0.15,
}) {
  if (today == null || baseline == null || baseline == 0) return null;
  final diffRatio = (today - baseline) / baseline;
  double raw = higherIsBetter ? diffRatio : -diffRatio;

  // 제한 범위 내로 정규화 (-1.0 ~ 1.0)
  if (raw > limitRatio) raw = limitRatio;
  if (raw < -limitRatio) raw = -limitRatio;

  return raw / limitRatio;
}

class _MetricDev {
  final String key;
  final double deviation;
  final double weight;
  _MetricDev(this.key, this.deviation, this.weight);
}

RecoveryScore _computeRecoveryScoreInternal({required NightRecoveryRaw today, required NightRecoveryBaseline baseline}) {
  final metrics = <_MetricDev>[];

  void _addMetric({required String key, required double? todayVal, required double? baseVal, required bool higherIsBetter, required double weight, double limitRatio = 0.15}) {
    final dev = _computeDeviationRatio(today: todayVal, baseline: baseVal, higherIsBetter: higherIsBetter, limitRatio: limitRatio);
    if (dev != null) metrics.add(_MetricDev(key, dev, weight));
  }

  // ✅ 1. 심박수 (야간 평균) - 가중치 40%, 민감도 높음(15%)
  _addMetric(key: 'hrMean', todayVal: today.hrMean, baseVal: baseline.hrMeanBase, higherIsBetter: false, weight: 0.40, limitRatio: 0.15);

  // ✅ 2. 수면 총량 - 가중치 30%, 민감도 낮음(40%까지 허용) -> 덜 잤어도 점수 덜 깎임
  if (today.sleepTotal != null && baseline.sleepTotalBase != null) {
    _addMetric(key: 'sleepTotal', todayVal: today.sleepTotal!.inMinutes.toDouble(), baseVal: baseline.sleepTotalBase!.inMinutes.toDouble(), higherIsBetter: true, weight: 0.30, limitRatio: 0.40);
  }

  // ✅ 3. HRV - 가중치 20%
  _addMetric(key: 'hrvRmssd', todayVal: today.hrvRmssd, baseVal: baseline.hrvRmssdBase, higherIsBetter: true, weight: 0.20, limitRatio: 0.20);

  // ✅ 4. 호흡수 - 가중치 10%
  _addMetric(key: 'respRate', todayVal: today.respRate, baseVal: baseline.respRateBase, higherIsBetter: false, weight: 0.10, limitRatio: 0.15);

  if (metrics.isEmpty) {
    return RecoveryScore(nightDate: today.nightDate, score: 50, label: RecoveryLabel.caution, metricContributions: const {}, lowConfidence: true);
  }

  final weightSum = metrics.fold<double>(0.0, (sum, m) => sum + m.weight);
  final normalized = metrics.fold<double>(0.0, (sum, m) => sum + m.deviation * (m.weight / weightSum)); // 결과는 -1.0 ~ 1.0

  // 🧮 점수 변환 보정
  // 평소와 똑같으면(0) -> 80점 (기존 60점에서 상향)
  // 편차 반영 비율 -> 35 (너무 극단적으로 깎이지 않게 조절)
  double rawScore = 80 + (normalized * 35);

  // 최소 점수 안전장치
  if (rawScore < 10) rawScore = 10;

  final score = rawScore.clamp(0.0, 100.0).round();

  // 라벨 기준
  final label = () {
    if (score >= 85) return RecoveryLabel.recoveryUp; // 85 이상: 최상
    if (score >= 65) return RecoveryLabel.good;       // 65 이상: 양호
    if (score >= 45) return RecoveryLabel.caution;    // 45 이상: 주의
    return RecoveryLabel.needRest;                    // 그 외: 휴식 필요
  }();

  return RecoveryScore(nightDate: today.nightDate, score: score, label: label, metricContributions: {for (final m in metrics) m.key: m.deviation}, lowConfidence: weightSum < 0.6);
}

RecoveryScore computeRecoveryFromNights(List<NightRecoveryRaw> nights) {
  if (nights.isEmpty) return RecoveryScore(nightDate: DateTime.now(), score: 50, label: RecoveryLabel.caution, metricContributions: const {}, lowConfidence: true);
  final baselines = computeNightBaselines(nights, minWindow: 3, maxWindow: 7);
  return _computeRecoveryScoreInternal(today: nights.last, baseline: baselines.last);
}