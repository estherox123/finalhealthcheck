// lib/pages/stress_recovery_page.dart
//
// 수면/심박 기반 회복 지표 상세 v0.1
// - 최근 최대 14박 데이터를 모아서, 동적 window(3~7박) 이동 중앙값 기준선 계산
// - 오늘 밤 수면 시간 + 야간 평균 심박 vs 기준선 → 0–100 점수
/// 오늘 몸 상태, 무리해도 되나? 에 다한 점수
// - UI는 HR/수면만 보여주고, HRV/호흡/SpO₂ 등은 아직 사용하지 않음
/// 회복 점수 계산하는 식 조금 더 검수 필요?

import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

import 'base_health_page.dart';
import 'sleep_detail_page.dart';
import '../data/recovery_score.dart' as rec;

class StressRecoveryPage extends HealthStatefulPage {
  const StressRecoveryPage({super.key});

  @override
  State<StressRecoveryPage> createState() => _StressRecoveryPageState();
}

class _StressRecoveryPageState extends HealthState<StressRecoveryPage> {
  @override
  List<HealthDataType> get types => const [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
  ];

  bool _loading = true;
  String? _localError;
  _RecoveryVm? _vm;

  @override
  void initState() {
    super.initState();
    authReady.then((_) {
      if (!mounted) return;
      _load();
    });
  }

  // ---------------- 공통 헬퍼 ----------------

  double? _numVal(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) {
      final n = v.numericValue;
      return n == null ? null : n.toDouble();
    }
    try {
      final any = (v as dynamic).numericValue;
      if (any is num) return any.toDouble();
    } catch (_) {}
    return null;
  }

  /// [winStart, winEnd) 수면 총합. ASLEEP 있으면 우선 사용, 없으면 SESSION.
  Future<Duration?> _sleepTotalInWindow(
      DateTime winStart, DateTime winEnd) async {
    try {
      final pts = await health.getHealthDataFromTypes(
        types: const [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_SESSION,
        ],
        startTime: winStart,
        endTime: winEnd,
      );
      final asleep =
      pts.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
      final base = asleep.isNotEmpty
          ? asleep
          : pts
          .where((p) => p.type == HealthDataType.SLEEP_SESSION)
          .toList();

      int minSum = 0;
      for (final p in base) {
        final a = p.dateFrom, b = p.dateTo;
        if (a == null || b == null) continue;
        final s = a.isAfter(winStart) ? a : winStart;
        final e = b.isBefore(winEnd) ? b : winEnd;
        final d = e.difference(s).inMinutes;
        if (d > 0) minSum += d;
      }
      if (minSum <= 0) return null;
      return Duration(minutes: minSum);
    } catch (_) {
      return null;
    }
  }

  /// 주어진 타입의 평균값(결측 시 null)
  Future<double?> _avgOfType(
      DateTime start, DateTime end, HealthDataType t) async {
    try {
      final pts = await health.getHealthDataFromTypes(
        types: [t],
        startTime: start,
        endTime: end,
      );
      final vals = <double>[];
      for (final p in pts) {
        final v = _numVal(p.value);
        if (v != null && v.isFinite) vals.add(v);
      }
      if (vals.isEmpty) return null;
      final sum = vals.reduce((a, b) => a + b);
      return sum / vals.length;
    } catch (_) {
      return null;
    }
  }

  // ---------------- 데이터 로딩 ----------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _localError = null;
    });

    try {
      if (!authorized) {
        _vm = null;
        _localError = '헬스 데이터 권한이 없어 회복 지표를 계산할 수 없습니다.';
        return;
      }

      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);

      // 최근 최대 14박까지 baseline용 raw 데이터 구성
      const maxHistoryDays = 14;
      final rawNights = <rec.NightRecoveryRaw>[];

      for (int i = maxHistoryDays; i >= 0; i--) {
        final anchor = today0.subtract(Duration(days: i));
        final winStart = anchor.subtract(const Duration(hours: 6)); // 18:00
        final winEnd = anchor.add(const Duration(hours: 12)); // 다음날 12:00

        final sleep = await _sleepTotalInWindow(winStart, winEnd);
        final hrMean = await _avgOfType(
          winStart,
          winEnd,
          HealthDataType.HEART_RATE,
        );

        // v0.1: HR + 수면만 사용. 나머지 필드는 null로 둠.
        const double? hrv = null;
        const double? resp = null;
        const int? awakenings = null;
        const double? spo2Min = null;

        if (sleep == null && hrMean == null) {
          // 완전히 비어 있는 밤은 스킵
          continue;
        }

        rawNights.add(
          rec.NightRecoveryRaw(
            nightDate: anchor,
            hrMean: hrMean,
            hrvRmssd: hrv,
            respRate: resp,
            sleepTotal: sleep,
            sleepAwakenings: awakenings,
            spo2Min: spo2Min,
          ),
        );
      }

      if (rawNights.isEmpty) {
        _vm = const _RecoveryVm(
          score: null,
          todayRaw: null,
          todayBaseline: null,
          nights: [],
          baselines: [],
        );
        return;
      }

      // 날짜 오름차순 정렬
      final nights = [...rawNights]
        ..sort((a, b) => a.nightDate.compareTo(b.nightDate));

      // 동적 window(3~7박) 기준선 + 회복 점수 계산
      final baselines = rec.computeNightBaselines(
        nights,
        minWindow: 3,
        maxWindow: 7,
      );
      final score = rec.computeRecoveryFromNights(nights);

      final todayRaw = nights.last;
      final todayBaseline = baselines.last;

      _vm = _RecoveryVm(
        score: score,
        todayRaw: todayRaw,
        todayBaseline: todayBaseline,
        nights: nights,
        baselines: baselines,
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('Recovery load error: $e\n$st');
      _localError = '회복 지표를 불러오는 중 오류가 발생했습니다.';
      _vm = null;
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: const Text('수면/심박 회복 지표'),
    );

    if (_loading) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMsg != null || _localError != null) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              errorMsg ?? _localError ?? '알 수 없는 오류',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final vm = _vm;
    if (vm == null || vm.score == null) {
      return Scaffold(
        appBar: appBar,
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Text(
                '최근 몇 밤 동안 수면/심박 데이터가 충분하지 않아\n'
                    '회복 지표를 계산할 수 없습니다.\n\n'
                    '워치를 착용하고 3일 이상 수면 기록이 쌓이면\n'
                    '오늘 회복 상태를 숫자로 볼 수 있습니다.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final score = vm.score!;
    final todayRaw = vm.todayRaw;
    final todayBaseline = vm.todayBaseline;

    final df = DateFormat('M/d (E)'); // 로케일 명시 없이 시스템 기본 사용
    final labelText = _recoveryLabelText(score.label);
    final labelColor = _recoveryLabelColor(score.label);

    final metrics = _buildMetricDetails(score, todayRaw, todayBaseline);

    return Scaffold(
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '최근 며칠 동안의 수면 시간과 야간 평균 심박수를\n'
                  '내 기준선과 비교해 오늘 회복 상태를 추정한 값입니다.\n'
                  '기준선은 최소 3박, 최대 최근 7박 데이터를 사용해 계산됩니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Text(
              '기상 기준 날짜: ${df.format(score.nightDate)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // ---- 회복 점수 카드 ----
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              color: labelColor.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 점수 크게
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '오늘 회복 점수 (수면/심박)',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                score.score.toString(),
                                style: Theme.of(context)
                                    .textTheme
                                    .displayMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: labelColor,
                                  fontSize: 44,       // ← 숫자 더 크게 고정
                                ),
                              ),
                              const SizedBox(width: 4),
                              Padding(
                                padding:
                                const EdgeInsets.only(bottom: 8.0, left: 2),
                                child: Text(
                                  '/ 100',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                    color: labelColor,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: labelColor.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  labelText,
                                  style: TextStyle(
                                    color: labelColor.darken(),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,        // ← 뱃지 글씨도 살짝 키움
                                  ),
                                ),
                              ),
                              if (score.lowConfidence) ...[
                                const SizedBox(width: 8),
                                const Text(
                                  '(데이터 적음)',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.bolt_outlined,
                      size: 40,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ---- 지표별 상세 ----
            const _SectionTitle('지표별 상세 (오늘 vs 기준선)'),
            if (metrics.isEmpty)
              const Text('지표별 상세를 계산할 수 있는 데이터가 부족합니다.')
            else
              Column(
                children: [
                  for (final m in metrics) ...[
                    _MetricCard(
                      metric: m,
                      onTap: () {
                        // key 기준으로 라우팅 분기
                        if (m.key == 'hrMean') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const _HrDetailWipPage(),
                            ),
                          );
                        } else if (m.key == 'sleepTotal') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SleepDetailPage(),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),


            // ---- 최근 밤 기록 ----
            const _SectionTitle('최근 수면/심박 기록'),
            if (vm.nights.isEmpty)
              const Text('최근 밤 데이터가 없습니다.')
            else
              _NightsTable(vm: vm),
            const SizedBox(height: 24),

            Text(
              '이 회복 지표는 개인 기준선 대비 수면 시간과 야간 심박수를 바탕으로 '
                  '상대적인 회복 상태를 보여주며, 의료적 판단을 대체하지 않습니다. '
                  '이상 증상이 느껴지면 반드시 의료진과 상의하세요.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 지표 상세 계산 ----------------

  List<_MetricDetail> _buildMetricDetails(
      rec.RecoveryScore score,
      rec.NightRecoveryRaw? raw,
      rec.NightRecoveryBaseline? base,
      ) {
    if (raw == null || base == null) return const [];

    double? diffRatio(double? today, double? baseline) {
      if (today == null || baseline == null || baseline == 0) return null;
      return (today - baseline) / baseline;
    }

    final metrics = <_MetricDetail>[];

    // 심박수 (야간 평균) — 낮을수록 좋음
    metrics.add(
      _MetricDetail(
        key: 'hrMean',
        title: '심박수 (야간 평균)',
        unit: 'bpm',
        today: raw.hrMean,
        baseline: base.hrMeanBase,
        higherIsBetter: false,
        diffRatio: diffRatio(raw.hrMean, base.hrMeanBase),
        valueFormat: (v) => v.toStringAsFixed(0),
      ),
    );

    // 총 수면 시간 — 길수록 좋음
    final todaySleepMin = raw.sleepTotal?.inMinutes.toDouble();
    final baseSleepMin = base.sleepTotalBase?.inMinutes.toDouble();

    metrics.add(
      _MetricDetail(
        key: 'sleepTotal',
        title: '총 수면 시간',
        unit: '',
        today: todaySleepMin,
        baseline: baseSleepMin,
        higherIsBetter: true,
        diffRatio: diffRatio(todaySleepMin, baseSleepMin),
        valueFormat: (v) {
          final h = (v ~/ 60).toInt();
          final m = (v % 60).round();
          return '${h}시간 ${m}분';
        },
      ),
    );

    return metrics
        .where((m) => m.today != null || m.baseline != null)
        .toList();
  }

  // ---------------- 라벨/색상 유틸 ----------------

  String _recoveryLabelText(rec.RecoveryLabel label) {
    switch (label) {
      case rec.RecoveryLabel.recoveryUp:
        return '회복↑';
      case rec.RecoveryLabel.good:
        return '양호';
      case rec.RecoveryLabel.caution:
        return '주의';
      case rec.RecoveryLabel.needRest:
        return '휴식 필요';
    }
  }

  Color _recoveryLabelColor(rec.RecoveryLabel label) {
    switch (label) {
      case rec.RecoveryLabel.recoveryUp:
        return Colors.green;
      case rec.RecoveryLabel.good:
        return Colors.blue;
      case rec.RecoveryLabel.caution:
        return Colors.orange;
      case rec.RecoveryLabel.needRest:
        return Colors.red;
    }
  }
}

// ---------------- ViewModel ----------------

class _RecoveryVm {
  final rec.RecoveryScore? score;
  final rec.NightRecoveryRaw? todayRaw;
  final rec.NightRecoveryBaseline? todayBaseline;
  final List<rec.NightRecoveryRaw> nights;
  final List<rec.NightRecoveryBaseline> baselines;

  const _RecoveryVm({
    required this.score,
    required this.todayRaw,
    required this.todayBaseline,
    required this.nights,
    required this.baselines,
  });
}

// ---------------- 지표 상세 모델/위젯 ----------------

class _MetricDetail {
  final String key;
  final String title;
  final String unit;
  final double? today;
  final double? baseline;
  final bool higherIsBetter;
  final double? diffRatio; // (today - baseline)/baseline
  final String Function(double value)? valueFormat;

  const _MetricDetail({
    required this.key,
    required this.title,
    required this.unit,
    required this.today,
    required this.baseline,
    required this.higherIsBetter,
    required this.diffRatio,
    this.valueFormat,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricDetail metric;
  final VoidCallback? onTap;
  const _MetricCard({required this.metric, this.onTap});

  @override
  Widget build(BuildContext context) {
    final today = metric.today;
    final baseline = metric.baseline;
    final diff = metric.diffRatio;

    String fmt(double? v) {
      if (v == null) return '-';
      if (metric.valueFormat != null) return metric.valueFormat!(v);
      return v.toStringAsFixed(1);
    }

    String diffLine() {
      if (diff == null) return '기준선과 비교할 수 있는 데이터가 부족합니다.';
      final pct = diff * 100;
      if (pct.abs() < 5) {
        return '기준선과 큰 차이는 없습니다.';
      }

      final sign = pct > 0 ? '+' : '';
      final better = metric.higherIsBetter ? pct > 0 : pct < 0; // 방향성 해석
      final dirWord = better ? '좋아짐' : '나빠짐';

      return '$sign${pct.toStringAsFixed(1)}% ($dirWord)';
    }

    IconData icon;
    Color iconColor;
    if (diff == null || diff.abs() < 0.05) {
      icon = Icons.horizontal_rule;
      iconColor = Colors.grey;
    } else {
      final better = metric.higherIsBetter ? diff > 0 : diff < 0;
      if (better) {
        icon = Icons.arrow_upward;
        iconColor = Colors.green;
      } else {
        icon = Icons.arrow_downward;
        iconColor = Colors.red;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목
                    Text(
                      metric.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 오늘 값
                    Text(
                      '오늘: ${fmt(today)}'
                          '${today == null || metric.unit.isEmpty ? '' : ' ${metric.unit}'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 18, // 너가 키워둔 부분
                      ),
                    ),
                    // 기준선
                    Text(
                      '기준선(최근 몇 박 중앙값): ${fmt(baseline)}'
                          '${baseline == null || metric.unit.isEmpty ? '' : ' ${metric.unit}'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 차이 설명
                    Text(
                      diffLine(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ---------------- 최근 밤 테이블 ----------------

class _NightsTable extends StatelessWidget {
  final _RecoveryVm vm;
  const _NightsTable({required this.vm});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('M/d');

    // 너무 길어지지 않게 최근 8박만 사용 (최신이 오른쪽으로 올수도, 왼쪽으로 올수도 취향)
    final all = vm.nights;
    if (all.isEmpty) {
      return const SizedBox.shrink();
    }

    final nights = all.length <= 8
        ? all
        : all.sublist(all.length - 8); // 최근 8개만

    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 4),
        itemCount: nights.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          // 최신 밤이 오른쪽 끝에 오도록 역순으로 표시
          final n = nights[nights.length - 1 - index];

          String dateLabel = df.format(n.nightDate);

          // 수면 시간 포맷
          final dur = n.sleepTotal;
          String sleepText;
          int? sleepMin;
          if (dur == null) {
            sleepText = '-';
          } else {
            sleepMin = dur.inMinutes;
            final h = sleepMin ~/ 60;
            final m = sleepMin % 60;
            sleepText = '${h}h ${m}m';
          }

          // HR 포맷
          final hr = n.hrMean;
          final hrText = hr == null ? '-' : '${hr.toStringAsFixed(0)} bpm';

          // 수면 상태에 따라 색/라벨
          Color bandColor;
          String badgeText;
          if (sleepMin == null) {
            bandColor = Colors.grey;
            badgeText = '기록 없음';
          } else if (sleepMin >= 420) {
            // 7h+
            bandColor = Colors.green;
            badgeText = '충분';
          } else if (sleepMin >= 300) {
            // 5h+
            bandColor = Colors.orange;
            badgeText = '조금 부족';
          } else {
            bandColor = Colors.red;
            badgeText = '많이 부족';
          }

          return Container(
            width: 130,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: Colors.black.withOpacity(0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 색 바
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: bandColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                ),
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 날짜
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                          fontSize: 14,          // ← 키움
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 수면 시간 크게
                      Text(
                        sleepText,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          fontSize: 20,          // ← 키움
                        ),
                      ),
                      const SizedBox(height: 2),
                      // HR
                      Text(
                        'HR  $hrText',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[800],
                          fontSize: 14,          // ← 키움
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 상태 뱃지
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: bandColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeText,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: bandColor.darken(0.1),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,        // ← 키움
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


// ---------------- 공통 위젯/유틸 ----------------

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
          fontSize: 22,   // ← 기존보다 살짝 키움
        ),
      ),
    );
  }
}

extension on Color {
  Color darken([double amount = .2]) {
    final hsl = HSLColor.fromColor(this);
    final hslDark =
    hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}

class _HrDetailWipPage extends StatelessWidget {
  const _HrDetailWipPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('심박수 상세')),
      body: const Center(
        child: Text(
          '심박수 상세 페이지는 추후 업데이트 예정입니다.\n'
              '현재는 야간 평균 심박만 회복 지표에 사용되고 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
