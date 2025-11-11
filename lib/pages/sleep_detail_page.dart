// lib/pages/sleep_detail_page.dart
/// 수면 데이터 페이지. 오늘 수면 시간 + 지난 7일 수면 그래프.
/// 현재 수면 시간만 있음. 워치 받고 나서 세분화?

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';
import 'base_health_page.dart';
import '../controllers/health_controller.dart';

class SleepDetailPage extends HealthStatefulPage {
  const SleepDetailPage({super.key});
  @override
  State<SleepDetailPage> createState() => _SleepDetailPageState();
}

class _SleepDetailPageState extends HealthState<SleepDetailPage> {
  @override
  List<HealthDataType> get types => const [HealthDataType.SLEEP_SESSION];

  Map<String, Duration> dailySleep = {};
  bool isLoadingData = false;
  Duration todaysSleep = Duration.zero;

  List<BarChartGroupData> barGroups = [];
  List<String> dateLabelsForChart = [];

  @override
  void initState() {
    super.initState();
    // 권한 초기화 완료 시점에 자동 로드
    authReady.then((ok) {
      if (!mounted) return;
      if (ok) _loadDailySleep();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-refresh when page becomes visible and is authorized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && authorized && !isLoadingData) {
        _loadDailySleep();
      }
    });
  }

  Future<void> _loadDailySleep() async {
    if (isLoadingData || !authorized) return;

    setState(() {
      isLoadingData = true;
      dailySleep.clear();
      barGroups.clear();
      dateLabelsForChart.clear();
      todaysSleep = Duration.zero;
    });

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

      // 오늘 수면 시간
      Duration today = Duration.zero;
      final sessions = await health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_SESSION],
        startTime: todayStart,
        endTime: todayEnd,
      );
      for (final session in sessions) {
        if (session.dateFrom != null && session.dateTo != null) {
          today += session.dateTo!.difference(session.dateFrom!);
        }
      }
      if (mounted) setState(() => todaysSleep = today);

      // 지난 7일
      final map = <String, Duration>{};
      for (int i = 6; i >= 0; i--) {
        final d = todayStart.subtract(Duration(days: i));
        final start = d;
        final end = d.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        Duration sleep = Duration.zero;

        if (i == 0) {
          sleep = today;
        } else {
          final sessions = await health.getHealthDataFromTypes(
            types: const [HealthDataType.SLEEP_SESSION],
            startTime: start,
            endTime: end,
          );
          for (final session in sessions) {
            if (session.dateFrom != null && session.dateTo != null) {
              sleep += session.dateTo!.difference(session.dateFrom!);
            }
          }
        }
        map[DateFormat('yyyy-MM-dd').format(start)] = sleep;
      }

      if (!mounted) return;
      setState(() {
        final keys = map.keys.toList()..sort();
        dailySleep = {for (final k in keys) k: map[k]!};
        _prepareBarChartData();
        isLoadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoadingData = false;
        errorMsg = '수면 데이터 로딩 실패: $e';
      });
    }
  }

  void _prepareBarChartData() {
    barGroups.clear();
    dateLabelsForChart.clear();
    final sorted = dailySleep.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (int i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final sleepHours = e.value.inMinutes / 60.0; // Convert to hours
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(
          toY: sleepHours,
          width: 16,
          color: Colors.indigo,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        )],
      ));
      // Convert English day names to Korean
      final dayOfWeek = DateTime.parse(e.key).weekday;
      final koreanDays = ['월', '화', '수', '목', '금', '토', '일'];
      dateLabelsForChart.add(koreanDays[dayOfWeek - 1]);
    }
  }

  double _getChartMaxY() {
    if (dailySleep.isEmpty) return 10.0;
    final maxVal = dailySleep.values.fold(0.0, (m, v) => v.inMinutes / 60.0 > m ? v.inMinutes / 60.0 : m);
    return (maxVal == 0 ? 5.0 : (maxVal * 1.2)).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final h = todaysSleep.inMinutes ~/ 60;
    final m = todaysSleep.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(title: const Text('지난 7일 수면')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (errorMsg != null)
              Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            //Text('권한: ${authorized ? "허용됨" : "미허용"}'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: authorized && !isLoadingData ? _loadDailySleep : null,
              icon: isLoadingData ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text('불러오기/새로고침'),
            ),
            const SizedBox(height: 16),
            if (authorized && !isLoadingData)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bedtime,
                      color: Colors.indigo[700],
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '수면 시간: ${h}시간 ${m}분',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo[700],
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
                      if (v % 2 != 0) return const SizedBox.shrink();
                      return SideTitleWidget(axisSide: m.axisSide, child: Text('${v.toInt()}시간', style: const TextStyle(fontSize: 10)));
                    })),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 2),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.indigo,
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (group.x < 0 || group.x >= dailySleep.keys.length) return null;
                        final dateKey = dailySleep.keys.elementAt(group.x);
                        final date = DateFormat('yyyy-MM-dd').parse(dateKey);
                        final hours = (rod.toY * 10).round() / 10; // Round to 1 decimal place
                        return BarTooltipItem(
                          '${date.month}/${date.day}\n',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          children: <TextSpan>[
                            TextSpan(text: '${hours.toStringAsFixed(1)}', style: const TextStyle(color: Colors.yellow, fontSize: 12, fontWeight: FontWeight.w500)),
                            const TextSpan(text: '시간', style: TextStyle(color: Colors.white, fontSize: 12)),
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
