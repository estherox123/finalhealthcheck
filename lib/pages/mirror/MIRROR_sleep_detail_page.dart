import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';

class MirrorSleepDetailPage extends StatefulWidget {
  const MirrorSleepDetailPage({super.key});
  @override
  State<MirrorSleepDetailPage> createState() => _MirrorSleepDetailPageState();
}

class _MirrorSleepDetailPageState extends State<MirrorSleepDetailPage> {
  late final HomeAssistantApi _api;
  bool _loading = true;

  List<({DateTime date, int minutes})> _historyData = [];

  // 데이터 상태 변수
  int _currentSleepMin = 0;
  String _todaySleepStr = "-";
  String _spo2Value = "-";
  String _targetStatus = "분석 중";

  @override
  void initState() {
    super.initState();
    _api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final prefix = _api.options.healthSensorPrefix; // sensor.sm_s931n_

      // 1. 현재 값 (PDF 기준 390.0)
      final sleepState = await _api.getState('${prefix}sleep_duration');
      // 소수점 제거 (390.0 -> 390)
      final currentSleepMin = double.tryParse(sleepState.state)?.toInt() ?? 0;

      final spo2State = await _api.getState('${prefix}oxygen_saturation');
      final spo2 = double.tryParse(spo2State.state);

      String tSleepStr = "0시간 0분";
      String tStatus = "부족"; // 기본값

      if (currentSleepMin > 0) {
        tSleepStr = "${currentSleepMin ~/ 60}시간 ${currentSleepMin % 60}분";
        // 7시간(420분) 이상이면 충분함, 5시간(300분) 이상이면 적당함
        if (currentSleepMin >= 420) tStatus = "충분함";
        else if (currentSleepMin >= 300) tStatus = "적당함";
        else tStatus = "부족함";
      }

      String tSpo2 = spo2 != null ? "${spo2.toStringAsFixed(0)}%" : "-";

      // 2. 히스토리 로딩
      final rawHistory = await _api.fetchHistory('${prefix}sleep_duration', days: 7);

      Map<String, int> dailyMax = {};

      for (var entry in rawHistory) {
        final val = double.tryParse(entry['state'])?.toInt() ?? 0;

        // 10분 미만 데이터는 노이즈로 간주하고 무시
        if (val < 10) continue;

        final dateStr = DateTime.parse(entry['last_updated']).toLocal().toString().split(' ')[0];

        if (!dailyMax.containsKey(dateStr) || val > dailyMax[dateStr]!) {
          dailyMax[dateStr] = val;
        }
      }

      // 오늘 현재 값도 히스토리에 반영
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (currentSleepMin > 10) {
        if (!dailyMax.containsKey(todayKey) || currentSleepMin > dailyMax[todayKey]!) {
          dailyMax[todayKey] = currentSleepMin;
        }
      }

      // 차트 데이터 변환
      List<({DateTime date, int minutes})> chartData = [];
      final now = DateTime.now();
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        final val = dailyMax[key] ?? 0;
        chartData.add((date: d, minutes: val));
      }

      if (mounted) {
        setState(() {
          _currentSleepMin = currentSleepMin;
          _todaySleepStr = tSleepStr;
          _targetStatus = tStatus; // 상태 업데이트
          _spo2Value = tSpo2;
          _historyData = chartData;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Sleep Page Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // ✅ 배경 완전 검정
      appBar: AppBar(
        title: const Text("수면 상세", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
        child: Column(
          children: [
            // 1. 메인 원형 그래프
            _buildCircularIndicator(),

            const SizedBox(height: 40),

            // 2. 정보 카드 (SpO2, 상태)
            _buildInfoCard(),

            const SizedBox(height: 30),

            // 3. 주간 차트
            Expanded(child: _buildWeeklyChartCard()),
          ],
        ),
      ),
    );
  }

  // 메인 원형 인디케이터
  Widget _buildCircularIndicator() {
    // 8시간(480분) 목표 기준 진행률
    double progress = (_currentSleepMin / 480.0).clamp(0.0, 1.0);

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 260, height: 260,
            child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 20,
                color: Colors.white10,
                strokeCap: StrokeCap.round
            ),
          ),
          SizedBox(
            width: 260, height: 260,
            child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 20,
                color: Colors.indigoAccent,
                backgroundColor: Colors.transparent,
                strokeCap: StrokeCap.round
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bedtime, color: Colors.indigoAccent, size: 36),
              const SizedBox(height: 8),
              Text(
                  _todaySleepStr,
                  style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)
              ),
              const SizedBox(height: 8),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      '목표 8시간',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)
                  )
              )
            ],
          )
        ],
      ),
    );
  }

  // 상세 정보 카드 (흰색)
  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _InfoItem(label: "산소 포화도", value: _spo2Value, icon: Icons.water_drop, color: Colors.blueAccent),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          _InfoItem(label: "수면 상태", value: _targetStatus, icon: Icons.analytics, color: Colors.green),
        ],
      ),
    );
  }

  // 주간 차트 카드 (흰색)
  Widget _buildWeeklyChartCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("주간 수면 트렌드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 600, // 10시간
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Y축 숨김
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        if (val.toInt() >= 0 && val.toInt() < _historyData.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat('M/d').format(_historyData[val.toInt()].date),
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
                barGroups: _historyData.asMap().entries.map((e) => BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.minutes.toDouble(),
                      color: e.value.minutes >= 420 ? Colors.indigoAccent : Colors.grey[300], // 7시간 이상이면 파랑
                      width: 18,
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: 600, // 배경 막대
                        color: Colors.grey[100],
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
  final String label; final String value; final IconData icon; final Color color;
  const _InfoItem({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 28),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.black87)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.black45, fontSize: 12)),
    ],
  );
}