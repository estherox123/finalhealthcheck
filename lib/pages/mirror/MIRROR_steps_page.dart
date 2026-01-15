import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

// API and Settings
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';

class MirrorStepsPage extends StatefulWidget {
  const MirrorStepsPage({super.key});

  @override
  State<MirrorStepsPage> createState() => _MirrorStepsPageState();
}

class _MirrorStepsPageState extends State<MirrorStepsPage> {
  late final HomeAssistantApi _api;

  // Data
  Map<String, int> dailySteps = {};
  List<MapEntry<String, int>> sortedDays = [];
  bool isLoadingData = true;

  // Today's Metrics
  int todaysSteps = 0;
  double todaysDistanceKm = 0.0;
  int todaysActivityMinutes = 0;
  int todaysCalories = 0;

  // Comparison Data
  int yesterdaySteps = 0;
  int avgSteps7 = 0;

  // Chart Data
  List<BarChartGroupData> barGroups = [];
  List<String> dateLabelsForChart = [];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  // ---------------- Calculation Logic ----------------

  double _estimateDistanceKm(int steps) => steps * 0.7 / 1000.0;
  int _estimateActivityMinutes(int steps) => steps <= 0 ? 0 : (steps / 100.0).round();
  int _estimateCalories(int steps) => (steps * 0.04).round();

  Future<void> _initAndLoad() async {
    try {
      final options = HomeAssistantOptions.fromEnv();
      _api = HomeAssistantApi(options: options);

      final entityId = '${options.healthSensorPrefix}daily_steps';

      // 1. Fetch Today's Live Data
      final state = await _api.getState(entityId);
      final currentSteps = double.tryParse(state.state)?.toInt() ?? 0;

      // 2. Fetch Past 7 Days Data
      final history = await _api.getHistory(entityId, days: 7);

      // 3. Process Data
      final processedMap = _processHistoryData(history, currentSteps);

      // 4. Calculate Metrics
      _calculateMetrics(processedMap, currentSteps);

      if (mounted) {
        setState(() {
          isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint("Mirror Steps Load Error: $e");
      if (mounted) setState(() => isLoadingData = false);
    }
  }

  Map<String, int> _processHistoryData(List<Map<String, dynamic>> history, int currentSteps) {
    Map<String, int> dailyMax = {};
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      dailyMax[key] = 0;
    }

    for (var item in history) {
      final val = double.tryParse(item['state'] ?? '')?.toInt();
      final timeStr = item['last_changed'];

      if (val != null && timeStr != null) {
        final dt = DateTime.parse(timeStr).toLocal();
        final key = DateFormat('yyyy-MM-dd').format(dt);

        if (dailyMax.containsKey(key)) {
          if (val > dailyMax[key]!) {
            dailyMax[key] = val;
          }
        }
      }
    }

    if ((dailyMax[todayKey] ?? 0) < currentSteps) {
      dailyMax[todayKey] = currentSteps;
    }

    return dailyMax;
  }

  void _calculateMetrics(Map<String, int> map, int current) {
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    dailySteps = map;
    sortedDays = dailySteps.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    todaysSteps = current;
    todaysDistanceKm = _estimateDistanceKm(current);
    todaysActivityMinutes = _estimateActivityMinutes(current);
    todaysCalories = _estimateCalories(current);

    yesterdaySteps = dailySteps[yesterdayKey] ?? 0;

    int total = 0;
    int count = 0;
    for (var entry in dailySteps.entries) {
      total += entry.value;
      count++;
    }
    avgSteps7 = count > 0 ? (total / count).round() : 0;

    _prepareBarChartData();
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
              width: 22, // ✅ [수정] 바 두께 확대 (18 -> 22)
              borderRadius: BorderRadius.circular(6),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: (avgSteps7 * 1.5).toDouble(),
                color: Colors.white10,
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

  // ---------------- UI Building ----------------

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###');
    double progress = avgSteps7 > 0 ? (todaysSteps / avgSteps7).clamp(0.0, 1.0) : 0.0;

    final diff = todaysSteps - yesterdaySteps;
    String insightText;
    if (diff > 0) {
      insightText = "어제보다 ${nf.format(diff)}걸음 더 걸으셨어요! 👏";
    } else if (diff < 0) {
      insightText = "어제보다 ${nf.format(diff.abs())}걸음 적네요. 힘내세요! 💪";
    } else {
      insightText = "어제와 똑같이 걸으셨네요!";
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('걸음 수', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 28)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
        actions: [
          IconButton(
            icon: isLoadingData
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                : const Icon(Icons.refresh, size: 30),
            onPressed: !isLoadingData ? _initAndLoad : null,
          )
        ],
      ),
      body: isLoadingData && dailySteps.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : RefreshIndicator(
        onRefresh: _initAndLoad,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          children: [
            _buildCircularIndicator(progress, nf),
            const SizedBox(height: 40),

            _buildInfoGrid(),
            const SizedBox(height: 30),

            // 인사이트 카드
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates, color: Colors.blueAccent, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      insightText,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            const Text("최근 7일 트렌드", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            _buildWeeklyChart(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularIndicator(double progress, NumberFormat nf) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 280, height: 280,
            child: CircularProgressIndicator(value: 1.0, strokeWidth: 22, color: Colors.grey[800], strokeCap: StrokeCap.round),
          ),
          SizedBox(
            width: 280, height: 280,
            child: CircularProgressIndicator(value: progress, strokeWidth: 22, color: const Color(0xFF4CAF50), backgroundColor: Colors.transparent, strokeCap: StrokeCap.round),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('오늘 걸음 수', style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(nf.format(todaysSteps), style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(16)),
                child: Text('목표 ${nf.format(avgSteps7)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoGrid() {
    return Row(
      children: [
        _buildInfoCard(icon: Icons.local_fire_department_rounded, color: Colors.orange, label: '칼로리', value: '$todaysCalories', unit: 'kcal'),
        const SizedBox(width: 16),
        _buildInfoCard(icon: Icons.place_outlined, color: Colors.blue, label: '거리', value: todaysDistanceKm.toStringAsFixed(1), unit: 'km'),
        const SizedBox(width: 16),
        _buildInfoCard(icon: Icons.timer_outlined, color: Colors.purple, label: '활동 시간', value: '$todaysActivityMinutes', unit: '분'),
      ],
    );
  }

  Widget _buildInfoCard({required IconData icon, required Color color, required String label, required String value, required String unit}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 32)),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 6),
            RichText(text: TextSpan(children: [
              TextSpan(text: value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const WidgetSpan(child: SizedBox(width: 4)),
              TextSpan(text: unit, style: const TextStyle(fontSize: 16, color: Colors.grey))
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart() {
    if (barGroups.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("데이터 없음", style: TextStyle(color: Colors.white, fontSize: 18))));

    double maxSteps = 0;
    for (var e in sortedDays) {
      if (e.value > maxSteps) maxSteps = e.value.toDouble();
    }
    // 최대값 설정 (최소 5000보)
    final maxY = (maxSteps < 5000 ? 5000.0 : maxSteps * 1.2);

    return Container(
      // ✅ [수정] 그래프 높이 확대 (300 -> 360)
      height: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              tooltipBgColor: Colors.black87,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x.toInt();
                final dateKey = sortedDays[idx].key;
                final date = DateTime.parse(dateKey);
                final steps = rod.toY.toInt();

                return BarTooltipItem(
                  '${DateFormat('MM/dd (E)', 'ko').format(date)}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  children: [
                    TextSpan(
                      text: NumberFormat('#,###').format(steps),
                      style: const TextStyle(color: Colors.yellowAccent, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: ' 걸음', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50, // '1만' 글씨 공간 확보
                getTitlesWidget: (value, meta) {
                  // ✅ [수정] '5천', '1만' 단위 표시 로직
                  if (value == 0) return const SizedBox();

                  // 만 단위
                  if (value % 10000 == 0) {
                    return Text('${(value/10000).toInt()}만', style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold));
                  }
                  // 천 단위 (5천 등)
                  else if (value % 1000 == 0) {
                    return Text('${(value/1000).toInt()}천', style: const TextStyle(color: Colors.grey, fontSize: 14));
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
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Text(
                        dateLabelsForChart[value.toInt()],
                        style: TextStyle(
                          color: value.toInt() == dateLabelsForChart.length - 1
                              ? const Color(0xFF4CAF50)
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 40,
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            // ✅ [수정] 5,000보 간격으로 그리드 (5천, 1만, 1만5천...)
            horizontalInterval: 5000,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}