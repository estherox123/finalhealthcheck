import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:health/health.dart';
import 'base_health_page.dart';

class StepsPage extends HealthStatefulPage {
  const StepsPage({super.key});
  @override
  State<StepsPage> createState() => _StepsPageState();
}

class _StepsPageState extends HealthState<StepsPage> {
  @override
  List<HealthDataType> get types => const [HealthDataType.STEPS];

  // yyyy-MM-dd → steps
  Map<String, int> dailySteps = {};
  // 차트/툴팁에서 동일하게 쓰는 정렬 리스트
  late List<MapEntry<String, int>> sortedDays = [];

  bool isLoadingData = false;
  int todaysSteps = 0;

  List<BarChartGroupData> barGroups = [];
  List<String> dateLabelsForChart = [];

  @override
  void initState() {
    super.initState();
    // 권한 초기화 완료 시점에 자동 로드
    authReady.then((ok) {
      if (!mounted) return;
      if (ok) _loadDailySteps();
    });
  }

  // HealthValue → double 안전 추출 (v13 대응)
  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) {
      final n = v.numericValue;
      return n == null ? null : n.toDouble();
    }
    return null;
  }

  Future<void> _loadDailySteps() async {
    if (isLoadingData || !authorized) return;

    setState(() {
      isLoadingData = true;
      dailySteps.clear();
      barGroups.clear();
      dateLabelsForChart.clear();
      todaysSteps = 0;
      sortedDays = [];
    });

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final tomorrowStart = todayStart.add(const Duration(days: 1));

      // ---------------- 오늘 합계 ----------------
      int today = 0;
      final aggregated = await health.getTotalStepsInInterval(todayStart, tomorrowStart);
      if (aggregated != null) {
        today = aggregated;
      } else {
        final pts = await health.getHealthDataFromTypes(
          types: const [HealthDataType.STEPS],
          startTime: todayStart,
          endTime: tomorrowStart, // end 미포함
        );
        for (final p in pts) {
          final d = _asDouble(p.value) ?? 0.0;
          today += d.round();
        }
      }
      if (mounted) setState(() => todaysSteps = today);

      // ---------------- 지난 7일(오늘 포함) ----------------
      final map = <String, int>{};
      for (int i = 6; i >= 0; i--) {
        final d = todayStart.subtract(Duration(days: i));
        final start = d;
        final end = d.add(const Duration(days: 1)); // end 미포함
        int steps = 0;

        if (i == 0) {
          steps = today; // 위에서 구한 값 재사용
        } else {
          final agg = await health.getTotalStepsInInterval(start, end);
          if (agg != null) {
            steps = agg;
          } else {
            final pts = await health.getHealthDataFromTypes(
              types: const [HealthDataType.STEPS],
              startTime: start,
              endTime: end,
            );
            for (final p in pts) {
              final dVal = _asDouble(p.value) ?? 0.0;
              steps += dVal.round();
            }
          }
        }
        map[DateFormat('yyyy-MM-dd').format(start)] = steps;
      }

      if (!mounted) return;
      setState(() {
        final keys = map.keys.toList()..sort();
        dailySteps = {for (final k in keys) k: map[k]!};
        // 차트/툴팁 공용 소스
        sortedDays = dailySteps.entries.toList();
        _prepareBarChartData(); // barGroups & dateLabelsForChart
        isLoadingData = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoadingData = false);
    }
  }

  void _prepareBarChartData() {
    barGroups.clear();
    dateLabelsForChart.clear();

    for (int i = 0; i < sortedDays.length; i++) {
      final e = sortedDays[i];
      final steps = e.value.toDouble();
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: steps,
              width: 16,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
            ),
          ],
        ),
      );

      final dayOfWeek = DateTime.parse(e.key).weekday;
      const koreanDays = ['월', '화', '수', '목', '금', '토', '일'];
      dateLabelsForChart.add(koreanDays[dayOfWeek - 1]);
    }
  }

  double _getChartMaxY() {
    if (dailySteps.isEmpty) return 10000;
    final maxVal = dailySteps.values.fold<int>(0, (m, v) => v > m ? v : m).toDouble();
    final scaled = (maxVal == 0 ? 5000 : (maxVal * 1.2));
    return scaled.clamp(1000, 100000).ceilToDouble();
  }

  double _horizontalInterval(double maxY) {
    final candidates = [1000.0, 2000.0, 5000.0, 10000.0, 20000.0];
    for (final c in candidates) {
      if (maxY / c <= 6) return c;
    }
    return maxY / 5.0;
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###');
    final maxY = _getChartMaxY();
    final interval = _horizontalInterval(maxY);

    return Scaffold(
      appBar: AppBar(title: const Text('지난 7일 걸음')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (errorMsg != null)
              Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            //Text('권한: ${authorized ? "허용됨" : "미허용"}'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: authorized && !isLoadingData ? _loadDailySteps : null,
              icon: isLoadingData
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text('불러오기/새로고침'),
            ),
            const SizedBox(height: 16),

            if (authorized && !isLoadingData)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_walk, color: Colors.teal[700], size: 28),
                    const SizedBox(width: 12),
                    Text(
                      '오늘: ${nf.format(todaysSteps)} 걸음',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[700],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            if (authorized && isLoadingData && barGroups.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator())),

            if (authorized && barGroups.isNotEmpty)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.28,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    barGroups: barGroups,
                    maxY: maxY,
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, m) {
                            final i = v.toInt();
                            if (i < 0 || i >= dateLabelsForChart.length) return const SizedBox.shrink();
                            return SideTitleWidget(
                              axisSide: m.axisSide,
                              child: Text(dateLabelsForChart[i], style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (v, m) {
                            if (v == m.max || v == m.min) return const SizedBox.shrink();
                            if (v.toInt() % interval.toInt() != 0) return const SizedBox.shrink();
                            return SideTitleWidget(
                              axisSide: m.axisSide,
                              child: Text(NumberFormat.compact().format(v.toInt()), style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: interval),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor: Colors.teal,
                        tooltipRoundedRadius: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final i = group.x.toInt();
                          if (i < 0 || i >= sortedDays.length) return null;
                          final entry = sortedDays[i];
                          final date = DateTime.parse(entry.key);
                          return BarTooltipItem(
                            '${date.month}/${date.day}\n',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            children: <TextSpan>[
                              TextSpan(text: '${rod.toY.toInt()}', style: const TextStyle(color: Colors.yellow, fontSize: 12, fontWeight: FontWeight.w600)),
                              const TextSpan(text: ' 걸음', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
