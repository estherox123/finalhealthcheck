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
    // API 초기화 (옵션 로드)
    final options = HomeAssistantOptions.fromEnv();
    _api = HomeAssistantApi(options: options);

    // 데이터 로드 시작
    _loadHaHistory();
  }

  Future<void> _loadHaHistory() async {
    setState(() => _isLoading = true);

    try {
      final prefix = _api.options.healthSensorPrefix; // 예: sensor.sm_s931n_
      if (prefix.isEmpty) throw Exception("HA_PHONE_PREFIX 설정이 없습니다.");

      // 1. 센서 이름 조합 (PDF 기반)
      final sysId = '${prefix}systolic_blood_pressure';
      final diaId = '${prefix}diastolic_blood_pressure';
      final pulseId = '${prefix}heart_rate';

      // 2. HA에서 기록 가져오기 (30일치)
      final results = await Future.wait([
        _api.fetchHistory(sysId, days: 30),
        _api.fetchHistory(diaId, days: 30),
        _api.fetchHistory(pulseId, days: 30),
      ]);

      final sysLog = results[0];
      final diaLog = results[1];
      final pulseLog = results[2];

      // 3. 데이터 병합 로직 (수축기 시간 기준, 이완기 매칭)
      List<_BpRecord> merged = [];

      for (var sItem in sysLog) {
        final stateStr = sItem['state'];
        if (stateStr == 'unavailable' || stateStr == 'unknown') continue;

        final sysVal = double.tryParse(stateStr)?.toInt() ?? 0;
        if (sysVal == 0) continue;

        final dateStr = sItem['last_updated']; // UTC 시간
        final date = DateTime.parse(dateStr).toLocal(); // 로컬 시간 변환

        // 같은 시간대(오차 5분)의 이완기 찾기
        final dItem = diaLog.firstWhere((d) {
          final dDate = DateTime.parse(d['last_updated']).toLocal();
          return dDate.difference(date).inMinutes.abs() < 5;
        }, orElse: () => {});

        // 같은 시간대(오차 5분)의 맥박 찾기
        final pItem = pulseLog.firstWhere((p) {
          final pDate = DateTime.parse(p['last_updated']).toLocal();
          return pDate.difference(date).inMinutes.abs() < 5;
        }, orElse: () => {});

        if (dItem.isNotEmpty) {
          final diaVal = double.tryParse(dItem['state'])?.toInt() ?? 0;
          final pulseVal = pItem.isNotEmpty ? double.tryParse(pItem['state'])?.toInt() : null;

          if (diaVal > 0) {
            merged.add(_BpRecord(date: date, sys: sysVal, dia: diaVal, pulse: pulseVal));
          }
        }
      }

      // 4. 최신순 정렬
      merged.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _history = merged;
          _latest = merged.isNotEmpty ? merged.first : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("HA History Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('혈압 관리 (HA 연동)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadHaHistory)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? Center(child: Text("기록이 없습니다.\nHA 센서($_api.options.healthSensorPrefix)를 확인하세요.", textAlign: TextAlign.center))
          : RefreshIndicator(
        onRefresh: _loadHaHistory,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_latest != null) _buildLatestCard(_latest!),
            const SizedBox(height: 24),
            const Text("최근 변화 (30일)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildLineChart(),
            const SizedBox(height: 24),
            const Text("상세 기록", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildHistoryList(),
          ],
        ),
      ),
    );
  }

  // ... (아래 _buildLatestCard, _buildLineChart, _buildHistoryList UI 코드는 이전과 100% 동일하므로 그대로 사용) ...
  // (UI 코드가 너무 길면 잘리니, 이전 코드의 UI 부분만 복사해서 붙여넣으시면 됩니다.)
  // (필요하시면 UI 코드도 다시 적어드릴까요?)

  // ▼▼▼ 이전 코드의 UI 부분 복사 시작 ▼▼▼

  Widget _buildLatestCard(_BpRecord record) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
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
                style: const TextStyle(color: Colors.grey, fontSize: 14),
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
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${record.sys}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.black87, height: 1.0)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('/', style: TextStyle(fontSize: 32, color: Colors.grey, fontWeight: FontWeight.w300)),
              ),
              Text('${record.dia}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.black87, height: 1.0)),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('mmHg', style: TextStyle(fontSize: 14, color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.monitor_heart, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              const Text("맥박", style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(width: 8),
              Text(
                record.pulse != null ? '${record.pulse}' : '-',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const Text(" bpm", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    final chartData = _history.take(15).toList().reversed.toList();
    if (chartData.isEmpty) return const SizedBox();

    return Container(
      height: 250,
      padding: const EdgeInsets.only(right: 20, left: 10, top: 20, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 40,
            getDrawingHorizontalLine: (value) {
              if (value == 120 || value == 80) {
                return FlLine(color: Colors.grey.withOpacity(0.5), strokeWidth: 1, dashArray: [4, 4]);
              }
              return FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1);
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
                          style: const TextStyle(color: Colors.grey, fontSize: 10),
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
                reservedSize: 35,
                interval: 40,
                getTitlesWidget: (val, meta) => Text(
                  '${val.toInt()}',
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: 40,
          maxY: 200,
          lineBarsData: [
            LineChartBarData(
              spots: chartData.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value.sys.toDouble());
              }).toList(),
              isCurved: true,
              color: Colors.redAccent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
            ),
            LineChartBarData(
              spots: chartData.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value.dia.toDouble());
              }).toList(),
              isCurved: true,
              color: Colors.blueAccent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final data = _history[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MM.dd').format(data.date),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text(
                    DateFormat('HH:mm').format(data.date),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                      Text('${data.sys}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text('/', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      Text('${data.dia}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const Text('mmHg', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  if (data.pulse != null)
                    Text('맥박 ${data.pulse}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(width: 16),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: data.statusColor, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }
}