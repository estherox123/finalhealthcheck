import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';

class MirrorStepsPage extends StatefulWidget {
  const MirrorStepsPage({super.key});
  @override
  State<MirrorStepsPage> createState() => _MirrorStepsPageState();
}

class _MirrorStepsPageState extends State<MirrorStepsPage> {
  late final HomeAssistantApi _api;
  bool isLoadingData = true;

  // 데이터 변수
  int todaysSteps = 0;
  double dist = 0;
  int cal = 0;
  int min = 0;

  List<MapEntry<String, int>> sortedDays = [];

  @override
  void initState() {
    super.initState();
    _api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    _loadHaStepsData();
  }

  Future<void> _loadHaStepsData() async {
    setState(() => isLoadingData = true);
    try {
      final prefix = _api.options.healthSensorPrefix; // sensor.sm_s931n_
      final stepsEntityId = '${prefix}daily_steps';

      // 1. 현재 값 (가장 중요: 무조건 표시)
      final currentState = await _api.getState(stepsEntityId);
      final currentSteps = double.tryParse(currentState.state)?.toInt() ?? 0;

      // 2. 히스토리 (없어도 괜찮음)
      Map<String, int> dailyMax = {};
      try {
        final history = await _api.fetchHistory(stepsEntityId, days: 7);
        for (var entry in history) {
          final val = double.tryParse(entry['state'])?.toInt() ?? 0;
          final date = DateTime.parse(entry['last_updated']).toLocal();
          final key = DateFormat('yyyy-MM-dd').format(date);
          // daily_steps는 누적 센서이므로 그날의 최대값이 최종 걸음수
          if (val > (dailyMax[key] ?? -1)) dailyMax[key] = val;
        }
      } catch (e) {
        debugPrint("History Fetch Failed: $e");
      }

      // ✅ [안전장치] 히스토리에 오늘 데이터가 없으면 현재 값으로 채움
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (currentSteps > 0) {
        dailyMax[todayKey] = currentSteps;
      }

      // 차트용 데이터 만들기
      sortedDays.clear();
      final now = DateTime.now();
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        // 데이터 없으면 0
        sortedDays.add(MapEntry(key, dailyMax[key] ?? 0));
      }

      if (mounted) {
        setState(() {
          todaysSteps = currentSteps;
          // 계산 로직
          dist = currentSteps * 0.7 / 1000;
          cal = (currentSteps * 0.04).round();
          min = (currentSteps / 100).round();
          isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => isLoadingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // ✅ 배경 완전 검정
      appBar: AppBar(
        title: const Text('활동량 상세', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
        child: Column(
          children: [
            // 1. 메인 원형 그래프 (검정 배경 위에 띄움)
            _buildCircularIndicator(),

            const SizedBox(height: 40),

            // 2. 상세 정보 그리드 (흰색 카드)
            _buildInfoCard(),

            const SizedBox(height: 30),

            // 3. 주간 차트 (흰색 카드)
            Expanded(child: _buildWeeklyChartCard()),
          ],
        ),
      ),
    );
  }

  // 메인 원형 인디케이터 (검정 배경용)
  Widget _buildCircularIndicator() {
    double progress = (todaysSteps / 10000).clamp(0.0, 1.0);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 배경 원 (어두운 회색)
          SizedBox(
            width: 260, height: 260,
            child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 20,
                color: Colors.white10, // 흐릿한 회색
                strokeCap: StrokeCap.round
            ),
          ),
          // 진행 원 (오렌지색)
          SizedBox(
            width: 260, height: 260,
            child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 20,
                color: Colors.orangeAccent,
                backgroundColor: Colors.transparent,
                strokeCap: StrokeCap.round
            ),
          ),
          // 중앙 텍스트
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_walk, color: Colors.orangeAccent, size: 36),
              const SizedBox(height: 8),
              Text(
                  NumberFormat('#,###').format(todaysSteps),
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)
              ),
              const Text('걸음', style: TextStyle(color: Colors.white54, fontSize: 18)),
              const SizedBox(height: 8),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      '목표 ${((progress * 100).toInt())}% 달성',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)
                  )
              )
            ],
          )
        ],
      ),
    );
  }

  // 상세 정보 카드 (흰색 배경)
  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white, // 흰색 카드
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _InfoItem(label: "활동 시간", value: "$min", unit: "분", icon: Icons.timer, color: Colors.purpleAccent),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          _InfoItem(label: "이동 거리", value: dist.toStringAsFixed(1), unit: "km", icon: Icons.place, color: Colors.blueAccent),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          _InfoItem(label: "소모 칼로리", value: "$cal", unit: "kcal", icon: Icons.local_fire_department, color: Colors.redAccent),
        ],
      ),
    );
  }

  // 주간 차트 카드 (흰색 배경)
  Widget _buildWeeklyChartCard() {
    if (sortedDays.isEmpty) return const Center(child: Text("데이터 없음", style: TextStyle(color: Colors.white)));

    double maxY = 10000;
    for (var e in sortedDays) if (e.value > maxY) maxY = e.value.toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white, // 흰색 카드
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("주간 활동 트렌드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.2,
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Y축 숨김 (깔끔하게)
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        if (val.toInt() >= 0 && val.toInt() < sortedDays.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              sortedDays[val.toInt()].key.substring(5), // 월-일
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: sortedDays.asMap().entries.map((e) => BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.value.toDouble(),
                      color: e.key == sortedDays.length - 1 ? Colors.orangeAccent : Colors.grey[300], // 오늘은 오렌지, 과거는 회색
                      width: 18,
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY * 1.2,
                        color: Colors.grey[100], // 막대 배경
                      ),
                    )
                  ],
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label; final String value; final String unit; final IconData icon; final Color color;
  const _InfoItem({required this.label, required this.value, required this.unit, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 28),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.black87)),
          const SizedBox(width: 2),
          Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.black45, fontSize: 12)),
    ],
  );
}