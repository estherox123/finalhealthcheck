// lib/pages/heart_rate_detail_page.dart
//
// 심박수 상세 페이지 v0.3
// - 지난 밤(어제 18:00 ~ 오늘 12:00) 평균/최저/최고 심박수
// - 지난 밤 심박수 추이 라인 차트
// - 최근 7일 평균 심박수 막대 그래프
// - 개인 7일 평균과의 비교 / 대략적인 범위 해석 텍스트
// - 글꼴 전체 1.12배 확대 + 설명 문단은 bodyMedium 사용

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';

import 'base_health_page.dart';

class HeartRateDetailPage extends HealthStatefulPage {
  const HeartRateDetailPage({super.key});

  @override
  State<HeartRateDetailPage> createState() => _HeartRateDetailPageState();
}

class _HeartRateDetailPageState extends HealthState<HeartRateDetailPage> {
  @override
  List<HealthDataType> get types => const [
    HealthDataType.HEART_RATE,
  ];

  bool _loading = true;
  String? _localError;
  _HrVm? _vm;

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

  // ---------------- 데이터 로딩 ----------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _localError = null;
      _vm = null;
    });

    try {
      if (!authorized) {
        _localError = '헬스 데이터 권한이 없어 심박수 정보를 불러올 수 없습니다.';
        return;
      }

      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);

      // "지난 밤" 윈도우: 어제 18:00 ~ 오늘 12:00 (수면 기준과 동일)
      final winAnchor = today0;
      final winStart = winAnchor.subtract(const Duration(hours: 6));
      final winEnd = winAnchor.add(const Duration(hours: 12));

      // 1) 지난 밤 심박수 타임라인 + 통계
      final hrPoints = await health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE],
        startTime: winStart,
        endTime: winEnd,
      );

      final samples = <_HrPoint>[];
      double? minHr, maxHr, sumHr;
      int count = 0;

      for (final p in hrPoints) {
        final v = _numVal(p.value);
        if (v == null) continue;
        final t = p.dateFrom ?? p.dateTo;
        if (t == null) continue;

        final vD = v.toDouble();
        samples.add(_HrPoint(time: t, bpm: vD));

        if (minHr == null || vD < minHr) minHr = vD;
        if (maxHr == null || vD > maxHr) maxHr = vD;
        sumHr = (sumHr ?? 0) + vD;
        count++;
      }

      final avgHr = (count > 0 && sumHr != null) ? (sumHr / count) : null;

      samples.sort((a, b) => a.time.compareTo(b.time));

      // 2) 최근 7일 평균 심박수 (같은 윈도우 기준)
      final last7Avg = <DateTime, double>{};
      for (int i = 6; i >= 0; i--) {
        final anchor = today0.subtract(Duration(days: i));
        final s = anchor.subtract(const Duration(hours: 6));
        final e = anchor.add(const Duration(hours: 12));

        final pts = await health.getHealthDataFromTypes(
          types: const [HealthDataType.HEART_RATE],
          startTime: s,
          endTime: e,
        );

        double sum = 0;
        int n = 0;
        for (final p in pts) {
          final v = _numVal(p.value);
          if (v == null) continue;
          sum += v;
          n++;
        }

        final avg = n > 0 ? (sum / n) : 0.0;
        last7Avg[anchor] = avg;
      }

      // 3) 최근 7일 개인 평균 (0만 있는 경우는 null 처리)
      double? avg7d;
      if (last7Avg.isNotEmpty) {
        double sum = 0;
        int n = 0;
        for (final v in last7Avg.values) {
          if (v <= 0) continue;
          sum += v;
          n++;
        }
        if (n > 0) avg7d = sum / n;
      }

      _vm = _HrVm(
        nightStart: winStart,
        nightEnd: winEnd,
        avgHr: avgHr,
        minHr: minHr,
        maxHr: maxHr,
        avg7d: avg7d,
        samples: samples,
        last7Avg: last7Avg,
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('HR load error: $e\n$st');
      _localError = '심박수 데이터를 불러오는 중 오류가 발생했습니다.';
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final scaledTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        fontSizeFactor: 1.12,
        heightFactor: 1.1,
      ),
    );

    final appBar = AppBar(
      title: const Text('심박수 요약'),
    );

    if (_loading) {
      return Theme(
        data: scaledTheme,
        child: Scaffold(
          appBar: appBar,
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (errorMsg != null || _localError != null) {
      return Theme(
        data: scaledTheme,
        child: Scaffold(
          appBar: appBar,
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  errorMsg ?? _localError ?? '알 수 없는 오류',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final vm = _vm;
    if (vm == null) {
      return Theme(
        data: scaledTheme,
        child: Scaffold(
          appBar: appBar,
          body: RefreshIndicator(
            onRefresh: _load,
            child: const Center(
              child: Text('심박수 데이터를 찾을 수 없습니다.'),
            ),
          ),
        ),
      );
    }

    final df = DateFormat('M/d');
    final nightLabel = '${df.format(vm.nightStart)} 기준 (어제 18:00 ~ 오늘 12:00)';

    return Theme(
      data: scaledTheme,
      child: Scaffold(
        appBar: appBar,
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    errorMsg!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),

              // 상단 설명: 여러 Text + SizedBox 로 문단 분리
              Text(
                '워치/폰에 기록된 심박수 데이터를 바탕으로',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700], height: 1.25),
              ),
              const SizedBox(height: 4),
              Text(
                '지난 밤 심박 상태와 최근 추세를 간단히 보여줍니다.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700], height: 1.25),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('불러오기/새로고침'),
                ),
              ),
              const SizedBox(height: 16),

              // -------- 지난 밤 요약 카드 --------
              _LastNightHrSummaryCard(vm: vm, nightLabel: nightLabel),
              const SizedBox(height: 16),

              // -------- 지난 밤 심박수 추이 라인 차트 --------
              _NightHrChart(vm: vm),
              const SizedBox(height: 24),

              // -------- 최근 7일 평균 심박수 막대 그래프 --------
              Text(
                '최근 7일 평균 심박수',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              // 설명 문단도 분리
              Text(
                '막대가 높을수록 해당 날 수면/야간 시간대의 심박수가 더 빨랐다는 뜻이에요.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700], height: 1.25),
              ),
              const SizedBox(height: 4),
              Text(
                '특정 날만 유독 높다면 그날의 컨디션(과로, 카페인, 스트레스 등)을 한 번 떠올려보세요.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700], height: 1.25),
              ),
              const SizedBox(height: 8),
              _Last7DaysHrChart(vm: vm),
              const SizedBox(height: 24),

              // 하단 안내 문단도 분리
              Text(
                '심박수는 개인차가 크고, 같은 사람도 그날의 컨디션에 따라 달라집니다.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700], height: 1.25),
              ),
              const SizedBox(height: 4),
              Text(
                '그래프는 “내 지난 일주일 패턴과 비교해서 어떠한지” 보는 용도로만 활용해주세요.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700], height: 1.25),
              ),
              const SizedBox(height: 4),
              Text(
                '가슴 두근거림, 어지럼증, 흉통 등 이상 증상이 반복되면 꼭 의료진과 상의하세요.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700], height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- ViewModel / 모델 ----------------

class _HrVm {
  final DateTime nightStart;
  final DateTime nightEnd;
  final double? avgHr;
  final double? minHr;
  final double? maxHr;
  final double? avg7d; // 최근 7일 개인 평균
  final List<_HrPoint> samples;
  final Map<DateTime, double> last7Avg;

  const _HrVm({
    required this.nightStart,
    required this.nightEnd,
    required this.avgHr,
    required this.minHr,
    required this.maxHr,
    required this.avg7d,
    required this.samples,
    required this.last7Avg,
  });
}

class _HrPoint {
  final DateTime time;
  final double bpm;
  _HrPoint({required this.time, required this.bpm});
}

// ---------------- 위젯: 지난 밤 요약 카드 ----------------

class _LastNightHrSummaryCard extends StatelessWidget {
  final _HrVm vm;
  final String nightLabel;

  const _LastNightHrSummaryCard({
    required this.vm,
    required this.nightLabel,
  });

  String _fmtBpm(double? v) {
    if (v == null) return '-';
    return '${v.round()} bpm';
  }

  String _rangeComment(double? v) {
    if (v == null) {
      return '기록이 부족해 일반적인 범위를 판단하기 어렵습니다.';
    }

    // 홈 대시보드의 hr 색상 기준과 대략 맞추기 (50~90 "보통")
    final hr = v;
    if (hr >= 50 && hr <= 90) {
      return '대부분의 성인 수면/휴식 시에서 자주 보이는 범위예요.';
    }
    if ((hr > 90 && hr <= 100) || (hr >= 45 && hr < 50)) {
      return '조금 벗어난 범위예요. 컨디션이 안 좋다면 오늘은 무리하지 않는 게 좋아요.';
    }
    return '평소와 많이 다르거나 불편한 증상이 있다면 의료진과 상의하는 것이 좋습니다.';
  }

  String? _vsBaselineComment(double? today, double? avg7d) {
    if (today == null || avg7d == null) return null;
    final diff = today - avg7d;
    final ad = diff.abs();

    if (ad < 3) {
      return '최근 1주 평균(${avg7d.round()} bpm)과 거의 비슷한 수준입니다.';
    }

    final dir = diff > 0 ? '조금 높은' : '조금 낮은';
    return '최근 1주 평균(${avg7d.round()} bpm)보다 약 ${ad.toStringAsFixed(1)} bpm $dir 편이에요.';
  }

  @override
  Widget build(BuildContext context) {
    final hasData = vm.avgHr != null;
    final baselineText = _vsBaselineComment(vm.avgHr, vm.avg7d);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.red.withOpacity(0.18),
            child: const Icon(Icons.favorite, color: Colors.red, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '지난 밤 평균 심박수',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasData ? _fmtBpm(vm.avgHr) : '기록 없음',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.red[700],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '최저: ${_fmtBpm(vm.minHr)}   ·   최고: ${_fmtBpm(vm.maxHr)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (vm.avg7d != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '최근 7일 평균: ${_fmtBpm(vm.avg7d)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (baselineText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    baselineText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  _rangeComment(vm.avgHr),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nightLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 위젯: 지난 밤 심박수 라인 차트 ----------------

class _NightHrChart extends StatelessWidget {
  final _HrVm vm;

  const _NightHrChart({required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.samples.isEmpty) {
      return const Text('지난 밤 심박수 기록이 없습니다.');
    }

    final samples = vm.samples;
    final start = vm.nightStart;

    final spots = <FlSpot>[];
    for (final p in samples) {
      final minutes = p.time.difference(start).inMinutes.toDouble();
      spots.add(FlSpot(minutes, p.bpm));
    }

    final xs = spots.map((e) => e.x).toList();
    final ys = spots.map((e) => e.y).toList();
    xs.sort();
    ys.sort();
    final minX = xs.first;
    final maxX = xs.last;

    final minY = ys.first;
    final maxY = ys.last;
    final yRange = (maxY - minY).abs();
    final yMargin =
    yRange == 0 ? 5.0 : (yRange * 0.2).clamp(4.0, 15.0); // 여유

    final chartMinY = (minY - yMargin).floorToDouble();
    final chartMaxY = (maxY + yMargin).ceilToDouble();

    final df = DateFormat('HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '지난 밤 심박수 추이',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '곡선이 부드럽게 유지되면 밤새 심장이 비교적 안정적으로 뛴다는 뜻이에요.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[700], height: 1.25),
        ),
        const SizedBox(height: 4),
        Text(
          '특정 구간에서만 갑자기 치솟거나 떨어지는 패턴이 반복되면, 그 시간대의 생활 패턴을 한 번 살펴보세요.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[700], height: 1.25),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: chartMinY,
              maxY: chartMaxY,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 5,
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final mid = (minX + maxX) / 2;
                      final isEdge = (value == minX || value == maxX);
                      final isMid = (value - mid).abs() < 1.0;
                      if (!isEdge && !isMid) {
                        return const SizedBox.shrink();
                      }
                      final t = start.add(Duration(minutes: value.round()));
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(
                          df.format(t),
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.max || value == meta.min) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                ),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 8,
                  getTooltipItems: (touchedSpots) {
                    if (touchedSpots.isEmpty) return [];
                    return touchedSpots.map((ts) {
                      final minutes = ts.x.round();
                      final t = start.add(Duration(minutes: minutes));
                      final bpm = ts.y;
                      return LineTooltipItem(
                        '${df.format(t)}\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: '${bpm.toStringAsFixed(0)} bpm',
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------- 최근 7일 평균 심박수 막대 그래프 ----------------

class _Last7DaysHrChart extends StatelessWidget {
  final _HrVm vm;

  const _Last7DaysHrChart({required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.last7Avg.isEmpty) {
      return const Text('최근 7일 심박수 데이터가 없습니다.');
    }

    final entries = vm.last7Avg.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final groups = <BarChartGroupData>[];
    final labels = <String>[];

    final koreanDays = ['월', '화', '수', '목', '금', '토', '일'];

    double maxBpm = 0;

    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final bpm = e.value;
      maxBpm = bpm > maxBpm ? bpm : maxBpm;

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: bpm,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );

      labels.add(koreanDays[e.key.weekday - 1]);
    }

    final maxY = (maxBpm == 0 ? 100.0 : (maxBpm * 1.2)).ceilToDouble();

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          barGroups: groups,
          maxY: maxY,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 10,
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      labels[i],
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == meta.max || value == meta.min) {
                    return const SizedBox.shrink();
                  }
                  if (value % 10 != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      '${value.toInt()}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x.toInt();
                if (idx < 0 || idx >= entries.length) return null;
                final date = entries[idx].key;
                final bpm = rod.toY;
                return BarTooltipItem(
                  '${date.month}/${date.day}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: bpm.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: ' bpm',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
