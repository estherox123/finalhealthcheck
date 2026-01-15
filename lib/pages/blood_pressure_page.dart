import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';

/// 혈압 데이터 모델
class _BpRecord {
  final DateTime date;
  final int sys; // 수축기
  final int dia; // 이완기
  final int? pulse; // 맥박

  _BpRecord({required this.date, required this.sys, required this.dia, this.pulse});

  // 상태 판별
  int get statusLevel {
    if (sys < 120 && dia < 80) return 0; // 정상
    if (sys < 140 && dia < 90) return 1; // 주의
    return 2; // 위험
  }

  String get statusText => ['정상', '주의', '고혈압'][statusLevel];
  Color get statusColor => [Colors.green, Colors.orange, Colors.redAccent][statusLevel];
}

class BloodPressurePage extends StatefulWidget {
  const BloodPressurePage({super.key});

  @override
  State<BloodPressurePage> createState() => _BloodPressurePageState();
}

class _BloodPressurePageState extends State<BloodPressurePage> {
  bool _isLoading = true;
  List<_BpRecord> _history = [];
  _BpRecord? _latest;
  late final HomeAssistantApi _api;

  @override
  void initState() {
    super.initState();
    _api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final prefix = _api.options.healthSensorPrefix;

      // 1. 현재 데이터
      final sysState = await _api.getState('${prefix}systolic_blood_pressure');
      final diaState = await _api.getState('${prefix}diastolic_blood_pressure');
      final pulseState = await _api.getState('${prefix}heart_rate');

      int currentSys = double.tryParse(sysState.state)?.toInt() ?? 0;
      int currentDia = double.tryParse(diaState.state)?.toInt() ?? 0;
      int currentPulse = double.tryParse(pulseState.state)?.toInt() ?? 0;

      if (currentSys > 0 && currentDia > 0) {
        _latest = _BpRecord(
            date: DateTime.now(),
            sys: currentSys,
            dia: currentDia,
            pulse: currentPulse > 0 ? currentPulse : null
        );
      }

      // 2. 과거 데이터 (30일)
      final sysHist = await _api.getHistory('${prefix}systolic_blood_pressure', days: 30);
      final diaHist = await _api.getHistory('${prefix}diastolic_blood_pressure', days: 30);

      // 3. 병합
      _history = _mergeHistory(sysHist, diaHist);

      if (_latest != null) {
        if (_history.isEmpty || _history.first.date.difference(_latest!.date).inMinutes.abs() > 10) {
          _history.insert(0, _latest!);
        }
      }

      setState(() => _isLoading = false);

    } catch (e) {
      debugPrint("BP Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_BpRecord> _mergeHistory(List<Map<String, dynamic>> sysList, List<Map<String, dynamic>> diaList) {
    List<_BpRecord> merged = [];
    DateTime parseDate(String? s) => DateTime.tryParse(s ?? '')?.toLocal() ?? DateTime(2000);

    for (var sItem in sysList) {
      int sVal = double.tryParse(sItem['state'].toString())?.toInt() ?? 0;
      if (sVal <= 0) continue;

      DateTime sTime = parseDate(sItem['last_changed']);

      var dItem = diaList.firstWhere(
            (d) => parseDate(d['last_changed']).difference(sTime).inMinutes.abs() < 30,
        orElse: () => {},
      );

      if (dItem.isNotEmpty) {
        int dVal = double.tryParse(dItem['state'].toString())?.toInt() ?? 0;
        if (dVal > 0) {
          merged.add(_BpRecord(date: sTime, sys: sVal, dia: dVal));
        }
      }
    }
    merged.sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final isMirror = MediaQuery.of(context).size.width > 600 || Theme.of(context).scaffoldBackgroundColor == Colors.black;
    final bgColor = isMirror ? Colors.black : const Color(0xFFF5F7FA);
    final cardColor = isMirror ? Colors.grey[900]! : Colors.white;
    final textColor = isMirror ? Colors.white : Colors.black87;
    // ✅ [수정] !를 붙여서 Color 타입을 보장 (잠재적 에러 방지)
    final Color subTextColor = isMirror ? Colors.grey : Colors.grey[600]!;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(backgroundColor: bgColor, elevation: 0, iconTheme: IconThemeData(color: textColor)),
        body: Center(child: CircularProgressIndicator(color: textColor)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('혈압 관리', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 24)),
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
          )
        ],
      ),
      body: _latest == null && _history.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: subTextColor),
            const SizedBox(height: 16),
            Text("기록이 없습니다.", style: TextStyle(color: subTextColor, fontSize: 18)),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_latest != null) _buildLatestCard(_latest!, cardColor, textColor, subTextColor),

            const SizedBox(height: 32),
            Text("최근 30일 변화", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 16),

            _buildLineChart(cardColor, textColor),

            const SizedBox(height: 32),
            Text("상세 기록", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 16),

            _buildHistoryList(cardColor, textColor, subTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestCard(_BpRecord record, Color cardBg, Color textCol, Color subCol) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MM월 dd일 (E) a h:mm', 'ko').format(record.date),
                style: TextStyle(color: subCol, fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: record.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: record.statusColor),
                ),
                child: Text(
                  record.statusText,
                  style: TextStyle(color: record.statusColor, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${record.sys}', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: textCol, height: 1.0)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text('/', style: TextStyle(fontSize: 40, color: subCol, fontWeight: FontWeight.w300)),
              ),
              Text('${record.dia}', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: textCol, height: 1.0)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('mmHg', style: TextStyle(fontSize: 16, color: subCol)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.grey.withOpacity(0.2)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite, color: Colors.redAccent, size: 24),
              const SizedBox(width: 8),
              Text("맥박", style: TextStyle(fontSize: 18, color: subCol)),
              const SizedBox(width: 8),
              Text(
                record.pulse != null && record.pulse! > 0 ? '${record.pulse}' : '-',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textCol),
              ),
              Text(" bpm", style: TextStyle(fontSize: 14, color: subCol)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLineChart(Color cardBg, Color textCol) {
    if (_history.isEmpty) return const SizedBox(height: 250, child: Center(child: Text("차트 데이터 없음")));

    final chartData = _history.take(15).toList().reversed.toList();

    return Container(
      height: 300,
      padding: const EdgeInsets.only(right: 24, left: 12, top: 24, bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 40,
            getDrawingHorizontalLine: (value) {
              if (value == 120 || value == 80) {
                return FlLine(color: Colors.green.withOpacity(0.5), strokeWidth: 1, dashArray: [4, 4]);
              }
              return FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1);
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (val, meta) {
                  final index = val.toInt();
                  if (index >= 0 && index < chartData.length) {
                    if (index == 0 || index == chartData.length - 1 || index == (chartData.length / 2).round()) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          DateFormat('M/d').format(chartData[index].date),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      );
                    }
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 40,
                getTitlesWidget: (val, meta) => Text(
                  '${val.toInt()}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: 40,
          maxY: 200,
          lineBarsData: [
            LineChartBarData(
              spots: chartData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.sys.toDouble())).toList(),
              isCurved: true,
              color: Colors.redAccent,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
            ),
            LineChartBarData(
              spots: chartData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.dia.toDouble())).toList(),
              isCurved: true,
              color: Colors.blueAccent,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.1)),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              // ✅ [수정] !를 붙여 에러 해결 (Color 타입 보장)
              tooltipBgColor: Colors.grey[800]!,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    "${spot.y.toInt()}",
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList(Color cardBg, Color textCol, Color subCol) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final data = _history[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MM.dd').format(data.date),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textCol),
                  ),
                  Text(
                    DateFormat('HH:mm').format(data.date),
                    style: TextStyle(fontSize: 14, color: subCol),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${data.sys}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textCol)),
                      Text('/', style: TextStyle(fontSize: 16, color: subCol)),
                      Text('${data.dia}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textCol)),
                      const SizedBox(width: 4),
                      Text('mmHg', style: TextStyle(fontSize: 12, color: subCol)),
                    ],
                  ),
                  if (data.pulse != null)
                    Text('맥박 ${data.pulse}', style: TextStyle(fontSize: 14, color: subCol)),
                ],
              ),
              const SizedBox(width: 16),
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: data.statusColor, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }
}