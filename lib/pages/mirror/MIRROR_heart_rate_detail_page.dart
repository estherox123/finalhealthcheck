import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';

class MirrorHeartRateDetailPage extends StatefulWidget {
  const MirrorHeartRateDetailPage({super.key});
  @override
  State<MirrorHeartRateDetailPage> createState() => _MirrorHeartRateDetailPageState();
}

class _MirrorHeartRateDetailPageState extends State<MirrorHeartRateDetailPage> {
  late final HomeAssistantApi _api;
  bool _loading = true;

  // 데이터 변수
  int _currentHr = 0;
  int _minHr = 0;
  int _maxHr = 0;
  int _avgHr = 0;
  List<FlSpot> _spots = [];

  @override
  void initState() {
    super.initState();
    _api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final prefix = _api.options.healthSensorPrefix;
      final hrEntityId = '${prefix}heart_rate';

      // 1. 현재 값 가져오기
      final stateObj = await _api.getState(hrEntityId);
      final currentVal = double.tryParse(stateObj.state)?.toInt() ?? 0;

      // 2. 히스토리 (오늘 0시부터 현재까지)
      List<FlSpot> spots = [];
      double min = 200;
      double max = 0;
      double sum = 0;
      int count = 0;

      try {
        // days: 0은 '오늘' 데이터를 의미
        final history = await _api.getHistory(hrEntityId, days: 0);
        final now = DateTime.now();
        final startOfDay = DateTime(now.year, now.month, now.day);

        // 데이터 샘플링 (최대 500개)
        int step = 1;
        if (history.length > 500) {
          step = (history.length / 500).ceil();
        }

        for (int i = 0; i < history.length; i += step) {
          final entry = history[i];
          final val = double.tryParse(entry['state'].toString());
          if (val == null || val <= 0) continue;

          final dateStr = entry['last_changed'];
          if (dateStr == null) continue;

          final date = DateTime.parse(dateStr).toLocal();

          if (date.isAfter(startOfDay)) {
            if (val < min) min = val;
            if (val > max) max = val;
            sum += val;
            count++;

            final x = date.difference(startOfDay).inMinutes.toDouble();
            spots.add(FlSpot(x, val));
          }
        }
      } catch (e) {
        debugPrint("History API Error: $e");
      }

      if (spots.isEmpty) {
        min = 0; max = 0;
      } else {
        if (currentVal > 0) {
          if (currentVal < min) min = currentVal.toDouble();
          if (currentVal > max) max = currentVal.toDouble();
        }
      }

      final avg = count > 0 ? (sum / count).toInt() : 0;

      if (mounted) {
        setState(() {
          _currentHr = currentVal;
          _minHr = min.toInt();
          _maxHr = max.toInt();
          _avgHr = avg;
          _spots = spots;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("HR Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('심박수 상세', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
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
            _buildCircularIndicator(),
            const SizedBox(height: 40),
            _buildInfoCard(),
            const SizedBox(height: 30),
            Expanded(child: _buildChartCard()),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularIndicator() {
    double progress = (_currentHr / 190.0).clamp(0.0, 1.0);

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 260, height: 260,
            child: CircularProgressIndicator(value: 1.0, strokeWidth: 20, color: Colors.white10, strokeCap: StrokeCap.round),
          ),
          SizedBox(
            width: 260, height: 260,
            child: CircularProgressIndicator(value: progress, strokeWidth: 20, color: Colors.redAccent, backgroundColor: Colors.transparent, strokeCap: StrokeCap.round),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite, color: Colors.redAccent, size: 40),
              const SizedBox(height: 8),
              Text(_currentHr > 0 ? "$_currentHr" : "-", style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)),
              const Text('bpm', style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                child: const Text('현재 심박수', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _InfoItem(label: "최저", value: _minHr > 0 ? "$_minHr" : "-", unit: "", icon: Icons.arrow_downward, color: Colors.blueAccent),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          _InfoItem(label: "평균", value: _avgHr > 0 ? "$_avgHr" : "-", unit: "", icon: Icons.show_chart, color: Colors.green),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          _InfoItem(label: "최고", value: _maxHr > 0 ? "$_maxHr" : "-", unit: "bpm", icon: Icons.arrow_upward, color: Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    // ✅ [수정 1] num 타입 에러 해결 (.toDouble() 추가)
    double chartMinY = (_minHr - 10).clamp(0, double.infinity).toDouble();
    double chartMaxY = (_maxHr + 10).toDouble();
    if (chartMaxY < chartMinY + 20) chartMaxY = chartMinY + 20;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 30, 24, 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Text("오늘의 심박수 흐름", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _spots.isEmpty
                ? const Center(child: Text("오늘 기록된 데이터가 없습니다.", style: TextStyle(color: Colors.grey)))
                : LineChart(
              LineChartData(
                minY: chartMinY,
                maxY: chartMaxY,
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 20, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[200], strokeWidth: 1)),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (val, _) {
                    if (val % 20 == 0) return Text("${val.toInt()}", style: const TextStyle(color: Colors.grey, fontSize: 10));
                    return const SizedBox();
                  })),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 180, getTitlesWidget: (val, _) {
                    int hour = (val / 60).floor();
                    if (hour % 6 == 0) return Text("$hour시", style: const TextStyle(color: Colors.grey, fontSize: 10));
                    return const SizedBox();
                  })),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [Colors.blueAccent, Colors.greenAccent, Colors.orangeAccent, Colors.redAccent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.redAccent.withOpacity(0.3), Colors.redAccent.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    // ✅ [수정 2] getTooltipColor 에러 해결 (tooltipBgColor 사용)
                    tooltipBgColor: Colors.black87,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          "${spot.y.toInt()} bpm",
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
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
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.black87)),
        const SizedBox(width: 2),
        Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.black45, fontSize: 12)),
    ],
  );
}