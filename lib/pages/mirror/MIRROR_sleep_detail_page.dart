import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

// API 및 설정
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';

class MirrorSleepDetailPage extends StatefulWidget {
  const MirrorSleepDetailPage({super.key});

  @override
  State<MirrorSleepDetailPage> createState() => _MirrorSleepDetailPageState();
}

class _MirrorSleepDetailPageState extends State<MirrorSleepDetailPage> {
  late final HomeAssistantApi _api;

  // 데이터
  Map<String, int> dailySleepMinutes = {}; // 날짜: 수면분(min)
  List<MapEntry<String, int>> sortedDays = [];
  bool isLoadingData = true;

  // 오늘 수치
  int todayDurationMin = 0; // 분 단위
  int todayCalculatedScore = 0; // 계산된 수면 점수

  // 비교 데이터
  int avgDurationMin7 = 0;

  // 차트 데이터
  List<BarChartGroupData> barGroups = [];
  List<String> dateLabelsForChart = [];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    try {
      final options = HomeAssistantOptions.fromEnv();
      _api = HomeAssistantApi(options: options);

      final durationEntity = '${options.healthSensorPrefix}sleep_duration';

      // 1. 오늘 수면 시간 가져오기
      final durationState = await _api.getState(durationEntity);
      final currentMin = double.tryParse(durationState.state)?.toInt() ?? 0;

      // 점수 계산 (8시간=480분 기준 100점)
      final calculatedScore = (currentMin / 480.0 * 100).clamp(0, 100).round();

      // 2. 과거 7일 데이터 가져오기 (History API)
      final history = await _api.getHistory(durationEntity, days: 7);

      // 3. 데이터 가공
      final processedMap = _processHistoryData(history, currentMin);

      // 4. 지표 계산 및 차트 준비
      _calculateMetrics(processedMap, currentMin, calculatedScore);

      if (mounted) {
        setState(() {
          isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint("Sleep Load Error: $e");
      if (mounted) setState(() => isLoadingData = false);
    }
  }

  // Raw 데이터에서 일별 최대 수면 시간 추출
  Map<String, int> _processHistoryData(List<Map<String, dynamic>> history, int currentMin) {
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

    if ((dailyMax[todayKey] ?? 0) < currentMin) {
      dailyMax[todayKey] = currentMin;
    }

    return dailyMax;
  }

  void _calculateMetrics(Map<String, int> map, int currentMin, int score) {
    dailySleepMinutes = map;
    sortedDays = dailySleepMinutes.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    todayDurationMin = currentMin;
    todayCalculatedScore = score;

    int total = 0;
    int count = 0;
    for (var entry in dailySleepMinutes.entries) {
      if (entry.value > 0) {
        total += entry.value;
        count++;
      }
    }
    avgDurationMin7 = count > 0 ? (total / count).round() : 0;

    _prepareBarChartData();
  }

  void _prepareBarChartData() {
    barGroups.clear();
    dateLabelsForChart.clear();

    for (int i = 0; i < sortedDays.length; i++) {
      final e = sortedDays[i];
      final minutes = e.value;
      final hours = minutes / 60.0;
      final isToday = i == sortedDays.length - 1;

      Color barColor;
      if (minutes >= 420) {
        barColor = const Color(0xFF5C6BC0);
      } else if (minutes >= 300) {
        barColor = const Color(0xFF66BB6A);
      } else {
        barColor = const Color(0xFFEF5350);
      }

      if (isToday) {
        barColor = barColor.withOpacity(1.0);
      } else {
        barColor = barColor.withOpacity(0.6);
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: hours,
              color: barColor,
              width: 22, // ✅ 바 두께 확대 (14 -> 22)
              borderRadius: BorderRadius.circular(6),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 9.0,
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

  // ---------------- UI 빌더 ----------------

  @override
  Widget build(BuildContext context) {
    double progress = todayDurationMin > 0 ? (todayDurationMin / 480.0).clamp(0.0, 1.0) : 0.0;

    final h = todayDurationMin ~/ 60;
    final m = todayDurationMin % 60;
    final timeStr = "${h}시간 ${m}분";

    String insightText = "충분한 휴식을 취하셨나요?";
    if (todayCalculatedScore >= 80) insightText = "푹 주무셨네요! 상쾌한 하루 되세요. ☀️";
    else if (todayCalculatedScore >= 60) insightText = "적당히 주무셨어요. 화이팅! 💪";
    else if (todayCalculatedScore > 0) insightText = "수면이 조금 부족해 보여요. 😴";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // ✅ 폰트 UP (20 -> 28)
        title: const Text('수면 분석', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 28)),
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
      body: isLoadingData && dailySleepMinutes.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.indigoAccent))
          : RefreshIndicator(
        onRefresh: _initAndLoad,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          children: [
            _buildCircularIndicator(progress, timeStr),
            const SizedBox(height: 40),

            _buildInfoGrid(),
            const SizedBox(height: 30),

            // 인사이트 카드
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.indigoAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.nights_stay, color: Colors.indigoAccent, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    // ✅ 폰트 UP (14 -> 18)
                    child: Text(
                      insightText,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigoAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // ✅ 폰트 UP (18 -> 24)
            const Text("최근 7일 수면 패턴", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            _buildWeeklyChart(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularIndicator(double progress, String timeStr) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 280, height: 280, // ✅ 크기 UP
            child: CircularProgressIndicator(value: 1.0, strokeWidth: 22, color: Colors.grey[800], strokeCap: StrokeCap.round),
          ),
          SizedBox(
            width: 280, height: 280,
            child: CircularProgressIndicator(value: progress, strokeWidth: 22, color: const Color(0xFF5C6BC0), backgroundColor: Colors.transparent, strokeCap: StrokeCap.round),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ 폰트 UP (14 -> 18)
              const Text('수면 시간', style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 8),
              // ✅ 폰트 UP (32 -> 48)
              Text(timeStr, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(16)),
                // ✅ 폰트 UP (12 -> 16)
                child: const Text('목표 8시간', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
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
        _buildInfoCard(
            icon: Icons.bedtime,
            color: Colors.indigoAccent,
            label: '총 수면',
            value: '${todayDurationMin ~/ 60}',
            unit: '시간 ${todayDurationMin % 60}분'
        ),
        const SizedBox(width: 16),
        _buildInfoCard(
            icon: Icons.grade,
            color: Colors.amber,
            label: '수면 점수',
            value: '$todayCalculatedScore',
            unit: '점'
        ),
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
            // ✅ 폰트 UP
            Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 6),
            RichText(text: TextSpan(children: [
              // ✅ 폰트 UP
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

    return Container(
      // ✅ 차트 높이 확대 (360)
      height: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 10,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              // ✅ 에러 수정: tooltipBgColor 사용
              tooltipBgColor: Colors.black87,
              // ✅ 에러 수정: getTooltipItem 사용 (단수형)
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x.toInt();
                final dateKey = sortedDays[idx].key;
                final date = DateTime.parse(dateKey);
                final minutes = sortedDays[idx].value;
                final h = minutes ~/ 60;
                final m = minutes % 60;

                return BarTooltipItem(
                  '${DateFormat('MM/dd (E)', 'ko').format(date)}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), // 툴팁 폰트 UP
                  children: [
                    TextSpan(
                      text: '$h시간 $m분',
                      style: const TextStyle(color: Colors.indigoAccent, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
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
                reservedSize: 35,
                interval: 2,
                getTitlesWidget: (value, meta) {
                  // ✅ 폰트 UP
                  return Text('${value.toInt()}h', style: const TextStyle(color: Colors.grey, fontSize: 14));
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
                      // ✅ 폰트 UP
                      child: Text(
                        dateLabelsForChart[value.toInt()],
                        style: TextStyle(
                          color: value.toInt() == dateLabelsForChart.length - 1
                              ? const Color(0xFF5C6BC0)
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
            horizontalInterval: 2,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}