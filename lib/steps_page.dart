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

  Map<String, int> dailySteps = {};
  bool isLoadingData = false;
  int todaysSteps = 0;

  List<BarChartGroupData> barGroups = [];
  List<String> dateLabelsForChart = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && authorized) _loadDailySteps();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-refresh when page becomes visible and is authorized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && authorized && !isLoadingData) {
        _loadDailySteps();
      }
    });
  }

  Future<void> _loadDailySteps() async {
    if (isLoadingData || !authorized) return;

    setState(() {
      isLoadingData = true;
      dailySteps.clear();
      barGroups.clear();
      dateLabelsForChart.clear();
      todaysSteps = 0;
    });

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

      // 오늘 합계
      int today = 0;
      final aggregated = await health.getTotalStepsInInterval(todayStart, todayEnd);
      if (aggregated != null) {
        today = aggregated;
      } else {
        final pts = await health.getHealthDataFromTypes(
          types: const [HealthDataType.STEPS],
          startTime: todayStart,
          endTime: todayEnd,
        );
        for (final p in pts) {
          final v = (p.value is num) ? (p.value as num).toDouble() : 0.0;
          today += v.round();
        }
      }
      if (mounted) setState(() => todaysSteps = today);

      // 지난 7일
      final map = <String, int>{};
      for (int i = 6; i >= 0; i--) {
        final d = todayStart.subtract(Duration(days: i));
        final start = d;
        final end = d.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        int steps = 0;

        if (i == 0) {
          steps = today;
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
              final v = (p.value is num) ? (p.value as num).toDouble() : 0.0;
              steps += v.round();
            }
          }
        }
        map[DateFormat('yyyy-MM-dd').format(start)] = steps;
      }

      if (!mounted) return;
      setState(() {
        final keys = map.keys.toList()..sort();
        dailySteps = {for (final k in keys) k: map[k]!};
        _prepareBarChartData();
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
    final sorted = dailySteps.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (int i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final steps = e.value.toDouble();
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: steps, width: 16, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)))],
      ));
      // Convert English day names to Korean
      final dayOfWeek = DateTime.parse(e.key).weekday;
      final koreanDays = ['월', '화', '수', '목', '금', '토', '일'];
      dateLabelsForChart.add(koreanDays[dayOfWeek - 1]);
    }
  }

  double _getChartMaxY() {
    if (dailySteps.isEmpty) return 10000;
    final maxVal = dailySteps.values.fold(0, (m, v) => v > m ? v : m).toDouble();
    return (maxVal == 0 ? 5000 : (maxVal * 1.2)).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###');
    return Scaffold(
      appBar: AppBar(title: const Text('지난 7일 걸음')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (errorMsg != null)
              Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Text('권한: ${authorized ? "허용됨" : "미허용"}'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: authorized && !isLoadingData ? _loadDailySteps : null,
              icon: isLoadingData ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
                    Icon(
                      Icons.directions_walk,
                      color: Colors.teal[700],
                      size: 28,
                    ),
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
                child: BarChart(BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: barGroups,
                  maxY: _getChartMaxY(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= dateLabelsForChart.length) return const SizedBox.shrink();
                      return SideTitleWidget(axisSide: m.axisSide, child: Text(dateLabelsForChart[i], style: const TextStyle(fontSize: 10)));
                    })),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) {
                      if (v == m.max || v == m.min) return const SizedBox.shrink();
                      if (v % 5000 != 0) return const SizedBox.shrink();
                      return SideTitleWidget(axisSide: m.axisSide, child: Text(NumberFormat.compact().format(v.toInt()), style: const TextStyle(fontSize: 10)));
                    })),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5000),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.teal,
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (group.x < 0 || group.x >= dailySteps.keys.length) return null;
                        final dateKey = dailySteps.keys.elementAt(group.x);
                        final date = DateFormat('yyyy-MM-dd').parse(dateKey);
                        return BarTooltipItem(
                          '${date.month}/${date.day}\n',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          children: <TextSpan>[
                            TextSpan(text: '${rod.toY.toInt()}', style: const TextStyle(color: Colors.yellow, fontSize: 12, fontWeight: FontWeight.w500)),
                            const TextSpan(text: ' 걸음', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        );
                      },
                    ),
                  ),
                )),
              ),
          ],
        ),
      ),
    );
  }
}
