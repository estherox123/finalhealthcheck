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

  // 데이터
  Map<String, int> dailySteps = {};
  List<MapEntry<String, int>> sortedDays = [];
  bool isLoadingData = false;

  // 오늘 수치
  int todaysSteps = 0;
  double todaysDistanceKm = 0.0;
  int todaysActivityMinutes = 0;
  int todaysCalories = 0;

  // 비교 데이터
  int yesterdaySteps = 0;
  int avgSteps7 = 0; // 7일 평균

  List<BarChartGroupData> barGroups = [];
  List<String> dateLabelsForChart = [];

  @override
  void initState() {
    super.initState();
    authReady.then((ok) {
      if (!mounted) return;
      if (ok) _loadDailySteps();
    });
  }

  // ---------------- 데이터 계산 로직 ----------------

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue?.toDouble();
    return null;
  }

  double _estimateDistanceKm(int steps) => steps * 0.7 / 1000.0;
  int _estimateActivityMinutes(int steps) => steps <= 0 ? 0 : (steps / 100.0).round();
  int _estimateCalories(int steps) => (steps * 0.04).round();

  Future<void> _loadDailySteps() async {
    if (isLoadingData || !authorized) return;

    setState(() {
      isLoadingData = true;
      dailySteps.clear();
      barGroups.clear();
      dateLabelsForChart.clear();
    });

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final tomorrowStart = todayStart.add(const Duration(days: 1));

      // 1. 오늘 걸음 수
      int today = 0;
      final aggregated = await health.getTotalStepsInInterval(todayStart, tomorrowStart);
      if (aggregated != null) {
        today = aggregated;
      } else {
        final pts = await health.getHealthDataFromTypes(
          types: const [HealthDataType.STEPS],
          startTime: todayStart,
          endTime: tomorrowStart,
        );
        for (final p in pts) {
          today += (_asDouble(p.value) ?? 0.0).round();
        }
      }

      // 2. 지난 7일 데이터
      final map = <String, int>{};
      int total7Days = 0;
      int count7Days = 0;
      int yesterday = 0;

      for (int i = 6; i >= 0; i--) {
        final d = todayStart.subtract(Duration(days: i));
        final start = d;
        final end = d.add(const Duration(days: 1));

        int steps = 0;
        if (i == 0) {
          steps = today;
        } else {
          final agg = await health.getTotalStepsInInterval(start, end);
          if (agg != null) {
            steps = agg;
          } else {
            final pts = await health.getHealthDataFromTypes(types: const [HealthDataType.STEPS], startTime: start, endTime: end);
            for (final p in pts) steps += (_asDouble(p.value) ?? 0.0).round();
          }
        }

        map[DateFormat('yyyy-MM-dd').format(start)] = steps;
        total7Days += steps;
        count7Days++;
        if (i == 1) yesterday = steps;
      }

      if (!mounted) return;
      setState(() {
        todaysSteps = today;
        todaysDistanceKm = _estimateDistanceKm(today);
        todaysActivityMinutes = _estimateActivityMinutes(today);
        todaysCalories = _estimateCalories(today);

        yesterdaySteps = yesterday;
        avgSteps7 = count7Days > 0 ? (total7Days / count7Days).round() : 1;

        final keys = map.keys.toList()..sort();
        dailySteps = {for (final k in keys) k: map[k]!};
        sortedDays = dailySteps.entries.toList();

        _prepareBarChartData();
        isLoadingData = false;
      });
    } catch (e) {
      debugPrint("Steps Load Error: $e");
      if (mounted) setState(() => isLoadingData = false);
    }
  }

  void _prepareBarChartData() {
    barGroups.clear();
    dateLabelsForChart.clear();

    for (int i = 0; i < sortedDays.length; i++) {
      final e = sortedDays[i];
      final steps = e.value.toDouble();
      final isToday = i == sortedDays.length - 1;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: steps,
              color: isToday ? const Color(0xFF4CAF50) : const Color(0xFFE0E0E0),
              width: 14,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: (avgSteps7 * 1.5).toDouble(),
                color: Colors.transparent,
              ),
            ),
          ],
        ),
      );

      final date = DateTime.parse(e.key);
      const days = ['월', '화', '수', '목', '금', '토', '일'];
      dateLabelsForChart.add(days[date.weekday - 1]);
    }
  }

  // ---------------- UI 빌더 ----------------

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###');

    // 목표 달성률 (최대 1.0)
    double progress = avgSteps7 > 0 ? (todaysSteps / avgSteps7).clamp(0.0, 1.0) : 0.0;

    // 어제 대비 문구
    final diff = todaysSteps - yesterdaySteps;
    String insightText;
    if (diff > 0) {
      insightText = "어제보다 ${nf.format(diff)}걸음 더 걸으셨어요! 👏";
    } else if (diff < 0) {
      insightText = "어제보다 ${nf.format(diff.abs())}걸음 적네요. 조금 더 힘내세요! 💪";
    } else {
      insightText = "어제와 똑같이 걸으셨네요!";
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('걸음 수', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: isLoadingData
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: !isLoadingData && authorized ? _loadDailySteps : null,
          )
        ],
      ),
      body: !authorized
          ? const Center(child: Text("권한이 필요합니다."))
          : RefreshIndicator(
        onRefresh: _loadDailySteps,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. 메인 원형 게이지
            _buildCircularIndicator(progress, nf),
            const SizedBox(height: 30),

            // 2. 상세 정보 그리드
            _buildInfoGrid(),
            const SizedBox(height: 20),

            // 3. 인사이트 카드
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates, color: Colors.blueAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      insightText,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // 4. 주간 차트 (개선됨 ✅)
            const Text("최근 7일 트렌드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildWeeklyChart(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 원형 프로그레스 바
  Widget _buildCircularIndicator(double progress, NumberFormat nf) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 220, height: 220,
            child: CircularProgressIndicator(value: 1.0, strokeWidth: 18, color: Colors.grey[200], strokeCap: StrokeCap.round),
          ),
          SizedBox(
            width: 220, height: 220,
            child: CircularProgressIndicator(value: progress, strokeWidth: 18, color: const Color(0xFF4CAF50), backgroundColor: Colors.transparent, strokeCap: StrokeCap.round),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('오늘 걸음 수', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(nf.format(todaysSteps), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.black87)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                child: Text('목표 ${nf.format(avgSteps7)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
            ],
          )
        ],
      ),
    );
  }

  // 정보 그리드
  Widget _buildInfoGrid() {
    return Row(
      children: [
        _buildInfoCard(icon: Icons.local_fire_department_rounded, color: Colors.orange, label: '칼로리', value: '$todaysCalories', unit: 'kcal'),
        const SizedBox(width: 12),
        _buildInfoCard(icon: Icons.place_outlined, color: Colors.blue, label: '거리', value: todaysDistanceKm.toStringAsFixed(1), unit: 'km'),
        const SizedBox(width: 12),
        _buildInfoCard(icon: Icons.timer_outlined, color: Colors.purple, label: '활동 시간', value: '$todaysActivityMinutes', unit: '분'),
      ],
    );
  }

  Widget _buildInfoCard({required IconData icon, required Color color, required String label, required String value, required String unit}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            RichText(text: TextSpan(children: [TextSpan(text: value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)), TextSpan(text: unit, style: const TextStyle(fontSize: 12, color: Colors.grey))])),
          ],
        ),
      ),
    );
  }

  // ✅ [업그레이드] 주간 차트 (Y축 라벨 + 툴팁 개선)
  Widget _buildWeeklyChart() {
    if (barGroups.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("데이터 없음")));

    // Y축 최대값 계산
    double maxSteps = 0;
    for (var e in sortedDays) {
      if (e.value > maxSteps) maxSteps = e.value.toDouble();
    }
    final maxY = (maxSteps < 5000 ? 5000.0 : maxSteps * 1.2);

    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x.toInt();
                final dateKey = sortedDays[idx].key;
                final date = DateTime.parse(dateKey);
                final steps = rod.toY.toInt();

                return BarTooltipItem(
                  '${DateFormat('MM/dd (E)', 'ko').format(date)}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  children: [
                    TextSpan(
                      text: NumberFormat('#,###').format(steps),
                      style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: ' 걸음', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            // ✅ 왼쪽 Y축 (걸음 수) 표시
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox();
                  // 10000 -> 10k, 5000 -> 5k 처럼 줄여서 표시하거나 그대로 표시
                  // 여기선 공간상 천 단위로 표시
                  if (value % 5000 == 0) {
                    return Text('${(value/1000).toInt()}k', style: const TextStyle(color: Colors.grey, fontSize: 10));
                  }
                  return const SizedBox();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < dateLabelsForChart.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        dateLabelsForChart[value.toInt()],
                        style: TextStyle(
                          color: value.toInt() == dateLabelsForChart.length - 1
                              ? const Color(0xFF4CAF50)
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 30,
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5000, // 5000보 단위 가로선
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[100], strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}