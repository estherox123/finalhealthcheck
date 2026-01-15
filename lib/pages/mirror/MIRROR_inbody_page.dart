import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:external_app_launcher/external_app_launcher.dart'; // ✅ 앱 실행기 추가

// API 및 설정
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';

class MirrorInBodyPage extends StatefulWidget {
  const MirrorInBodyPage({super.key});

  @override
  State<MirrorInBodyPage> createState() => _MirrorInBodyPageState();
}

class _MirrorInBodyPageState extends State<MirrorInBodyPage> {
  late final HomeAssistantApi _api;
  bool _loading = true;

  // 데이터 변수
  double _weight = 0;
  double _height = 175.0; // 기본값
  double _bodyFat = 0;
  double _muscle = 0;
  double _bmr = 0;

  // 차트 데이터
  List<FlSpot> _weightHistory = [];
  double _minWeight = 0;
  double _maxWeight = 0;

  @override
  void initState() {
    super.initState();
    _api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    _loadData();
  }

  // 실시간 BMI 계산
  double get _currentBmi {
    if (_weight <= 0 || _height <= 0) return 0;
    double hM = _height / 100.0;
    return _weight / (hM * hM);
  }

  // 실시간 상태 태그 (체지방률 우선)
  ({String text, Color color}) get _analyzeStatus {
    if (_bodyFat > 0) {
      if (_bodyFat < 18) return (text: "체지방 낮음", color: Colors.blue);
      if (_bodyFat <= 28) return (text: "표준", color: Colors.green);
      if (_bodyFat <= 35) return (text: "경도 비만", color: Colors.orange);
      return (text: "비만", color: Colors.redAccent);
    }

    double currentBmi = _currentBmi;
    if (currentBmi == 0) return (text: "측정 필요", color: Colors.grey);
    if (currentBmi < 18.5) return (text: "저체중", color: Colors.blue);
    if (currentBmi < 23.0) return (text: "정상", color: Colors.green);
    if (currentBmi < 25.0) return (text: "과체중", color: Colors.orange);
    return (text: "비만", color: Colors.redAccent);
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final prefix = _api.options.healthSensorPrefix;

      final wState = await _api.getState('${prefix}weight');
      final bfState = await _api.getState('${prefix}body_fat');
      final mState = await _api.getState('${prefix}skeletal_muscle_mass');
      final bmrState = await _api.getState('${prefix}basal_metabolic_rate');

      final heightState = await _api.getState('input_number.user_height');

      double w = double.tryParse(wState.state) ?? 0;
      if (w > 300) w /= 1000.0;

      double h = double.tryParse(heightState.state) ?? 175.0;
      double bf = double.tryParse(bfState.state) ?? 0;
      double mus = double.tryParse(mState.state) ?? 0;
      double bmr = double.tryParse(bmrState.state) ?? 0;

      final history = await _api.getHistory('${prefix}weight', days: 30);
      List<FlSpot> spots = [];
      double minW = 200.0;
      double maxW = 0.0;

      for (var item in history) {
        final valStr = item['state'];
        final dateStr = item['last_changed'];
        if (valStr == null || dateStr == null) continue;

        double val = double.tryParse(valStr.toString()) ?? 0;
        if (val > 300) val /= 1000.0;
        if (val <= 0) continue;

        if (val < minW) minW = val;
        if (val > maxW) maxW = val;

        final date = DateTime.parse(dateStr).toLocal();
        final diff = DateTime.now().difference(date).inDays;
        final x = (30 - diff).toDouble();
        spots.add(FlSpot(x, val));
      }
      spots.sort((a, b) => a.x.compareTo(b.x));

      if (mounted) {
        setState(() {
          _weight = w;
          _height = h;
          _bodyFat = bf;
          _muscle = mus;
          _bmr = bmr;
          _weightHistory = spots;
          _minWeight = minW;
          _maxWeight = maxW;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("InBody Load Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // 키 저장 로직
  Future<void> _updateHeight(String valueStr) async {
    double? newHeight = double.tryParse(valueStr);
    if (newHeight == null || newHeight < 50 || newHeight > 250) return;

    setState(() { _height = newHeight; });

    try {
      await _api.callService(
        domain: 'input_number',
        service: 'set_value',
        entityId: 'input_number.user_height',
        data: {
          'entity_id': 'input_number.user_height',
          'value': newHeight
        },
      );
    } catch (e) {
      debugPrint("Height Save Error: $e");
    }
  }

  // ✅ [추가] 앱 실행 함수
  Future<void> _launchInBodyApp() async {
    await LaunchApp.openApp(
      androidPackageName: 'com.inbody2014.inbody',
      iosUrlScheme: 'inbody://',
      appStoreLink: 'https://apps.apple.com/kr/app/inbody/id884923678',
      openStore: true,
    );
  }

  void _showHeightDialog() {
    final TextEditingController controller = TextEditingController(text: _height.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(30),
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("키 입력", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    suffixText: "cm",
                    suffixStyle: const TextStyle(color: Colors.grey, fontSize: 20),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent.withOpacity(0.5))),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent, width: 2)),
                  ),
                  autofocus: true,
                  onSubmitted: (val) {
                    _updateHeight(val);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: Colors.grey, fontSize: 18))),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () { _updateHeight(controller.text); Navigator.pop(context); },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text("저장", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _analyzeStatus;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('체성분 분석', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 30), onPressed: _loadData)
        ],
      ),
      body: _loading && _weight == 0
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          children: [
            _buildMainWeightCard(status.text, status.color),
            const SizedBox(height: 40),
            _buildDetailGrid(),
            const SizedBox(height: 40),
            const Text("최근 30일 체중 변화", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            _buildWeightChart(),
            const SizedBox(height: 40),

            // ✅ [추가] 인바디 앱 실행 버튼 (미러 테마 적용)
            SizedBox(
              width: double.infinity,
              height: 64, // 버튼 크기 큼직하게
              child: ElevatedButton.icon(
                onPressed: _launchInBodyApp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCA202D), // 인바디 브랜드 컬러
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                ),
                icon: const Icon(Icons.open_in_new, size: 28),
                label: const Text("InBody 앱 열기", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            const Center(child: Text("그래프 및 변화 분석은 공식 앱을 이용하세요.", style: TextStyle(fontSize: 14, color: Colors.grey))),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildMainWeightCard(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(30), border: Border.all(color: color.withOpacity(0.3), width: 2), boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)]),
      child: Column(
        children: [
          const Text("현재 체중", style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_weight > 0 ? _weight.toStringAsFixed(1) : "-", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)),
              const SizedBox(width: 8),
              const Text("kg", style: TextStyle(fontSize: 24, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailGrid() {
    return GridView.count(
      crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.4, crossAxisSpacing: 20, mainAxisSpacing: 20,
      children: [
        _DetailCard(icon: Icons.height, color: Colors.blueAccent, label: "나의 키", value: _height.toStringAsFixed(1), unit: "cm", onTap: _showHeightDialog),
        _DetailCard(icon: Icons.accessibility_new, color: Colors.greenAccent, label: "BMI", value: _currentBmi > 0 ? _currentBmi.toStringAsFixed(1) : "-", unit: ""),
        _DetailCard(icon: Icons.opacity, color: Colors.cyanAccent, label: "체지방률", value: _bodyFat > 0 ? _bodyFat.toStringAsFixed(1) : "-", unit: "%"),
        _DetailCard(icon: Icons.local_fire_department, color: Colors.orangeAccent, label: "기초대사량", value: _bmr > 0 ? _bmr.toStringAsFixed(0) : "-", unit: "kcal"),
      ],
    );
  }

  Widget _buildWeightChart() {
    if (_weightHistory.isEmpty) return const SizedBox(height: 300, child: Center(child: Text("기록된 데이터가 없습니다.", style: TextStyle(color: Colors.grey, fontSize: 18))));
    double minY = (_minWeight - 2.0).clamp(0, 500); double maxY = _maxWeight + 2.0;
    return Container(
      height: 350, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(24)),
      child: LineChart(LineChartData(
        minY: minY, maxY: maxY,
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1)),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: 5, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 14)))),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _weightHistory, isCurved: true, gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.cyanAccent]), barWidth: 4, isStrokeCapRound: true,
            dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: Colors.white, strokeWidth: 2, strokeColor: Colors.blueAccent)),
            belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.blueAccent.withOpacity(0.3), Colors.blueAccent.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          ),
        ],
        lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(tooltipBgColor: Colors.black87, getTooltipItems: (touchedSpots) { return touchedSpots.map((spot) => LineTooltipItem("${spot.y.toStringAsFixed(1)} kg", const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))).toList(); })),
      )),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon; final Color color; final String label; final String value; final String unit; final VoidCallback? onTap;
  const _DetailCard({required this.icon, required this.color, required this.label, required this.value, required this.unit, this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(24),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16), decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(24)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color, size: 36), const SizedBox(height: 12), Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)), const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)), if (unit.isNotEmpty) ...[const SizedBox(width: 4), Text(unit, style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold))]]), if (onTap != null) ...[const SizedBox(height: 4), const Icon(Icons.edit, size: 14, color: Colors.grey)]])),
    );
  }
}