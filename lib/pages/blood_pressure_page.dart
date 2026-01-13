// lib/pages/blood_pressure_page.dart

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
  bool _isLoadingLatest = true; // 현재 상태 로딩 중
  bool _isLoadingHistory = true; // 과거 기록 로딩 중

  List<_BpRecord> _history = [];
  _BpRecord? _latest;
  late final HomeAssistantApi _api;

  @override
  void initState() {
    super.initState();
    final options = HomeAssistantOptions.fromEnv();
    _api = HomeAssistantApi(options: options);

    // 1. 현재 데이터 먼저 로딩 (빠름)
    _loadCurrentData();
    // 2. 과거 기록 나중에 로딩 (느림)
    _loadHistoryData();
  }

  /// ✅ 1단계: 현재 상태만 빠르게 조회
  Future<void> _loadCurrentData() async {
    try {
      final currentData = await _api.fetchInbodyData(); // 이미 있는 메서드 재활용

      if (currentData['systolic']! > 0 && currentData['diastolic']! > 0) {
        final now = DateTime.now();
        final record = _BpRecord(
          date: now,
          sys: currentData['systolic']!.toInt(),
          dia: currentData['diastolic']!.toInt(),
          pulse: currentData['pulse']?.toInt(),
        );

        if (mounted) {
          setState(() {
            _latest = record;
            // 히스토리 로딩 전이라도 일단 리스트에 넣어둠
            if (_history.isEmpty) _history = [record];
            _isLoadingLatest = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingLatest = false);
      }
    } catch (e) {
      debugPrint("Current BP Load Error: $e");
      if (mounted) setState(() => _isLoadingLatest = false);
    }
  }

  /// ✅ 2단계: 과거 30일치 기록 조회
  Future<void> _loadHistoryData() async {
    try {
      final prefix = _api.options.healthSensorPrefix;
      if (prefix.isEmpty) return;

      final sysId = '${prefix}systolic_blood_pressure';
      final diaId = '${prefix}diastolic_blood_pressure';
      final pulseId = '${prefix}heart_rate';

      final results = await Future.wait([
        _api.fetchHistory(sysId, days: 30),
        _api.fetchHistory(diaId, days: 30),
        _api.fetchHistory(pulseId, days: 30),
      ]);

      final sysLog = results[0];
      final diaLog = results[1];
      final pulseLog = results[2];

      List<_BpRecord> merged = [];

      for (var sItem in sysLog) {
        final stateStr = sItem['state'];
        if (stateStr == 'unavailable' || stateStr == 'unknown') continue;
        final sysVal = double.tryParse(stateStr)?.toInt() ?? 0;
        if (sysVal == 0) continue;

        final date = DateTime.parse(sItem['last_updated']).toLocal();

        // 매칭 범위 30분으로 넉넉하게 잡음
        final dItem = diaLog.firstWhere((d) {
          final dDate = DateTime.parse(d['last_updated']).toLocal();
          return dDate.difference(date).inMinutes.abs() < 30;
        }, orElse: () => {});

        final pItem = pulseLog.firstWhere((p) {
          final pDate = DateTime.parse(p['last_updated']).toLocal();
          return pDate.difference(date).inMinutes.abs() < 30;
        }, orElse: () => {});

        if (dItem.isNotEmpty) {
          final diaVal = double.tryParse(dItem['state'])?.toInt() ?? 0;
          final pulseVal = pItem.isNotEmpty ? double.tryParse(pItem['state'])?.toInt() : null;
          if (diaVal > 0) {
            merged.add(_BpRecord(date: date, sys: sysVal, dia: diaVal, pulse: pulseVal));
          }
        }
      }

      // 현재 _latest 값이 있다면 중복 체크 후 추가
      if (_latest != null) {
        bool exists = merged.any((r) =>
        r.sys == _latest!.sys && r.dia == _latest!.dia &&
            r.date.difference(_latest!.date).inMinutes.abs() < 60
        );
        if (!exists) merged.add(_latest!);
      }

      // 최신순 정렬
      merged.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _history = merged;
          if (merged.isNotEmpty) _latest = merged.first; // 최신값 갱신
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint("HA History Load Error: $e");
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 적어도 현재 데이터 로딩은 끝나야 화면을 보여줌
    // (히스토리는 로딩 중이어도 차트 자리만 비워두고 보여줌)
    if (_isLoadingLatest) {
      return Scaffold(
        appBar: AppBar(title: const Text('혈압 관리'), backgroundColor: const Color(0xFFF5F7FA), elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('혈압 관리', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() { _isLoadingLatest = true; _isLoadingHistory = true; });
                _loadCurrentData();
                _loadHistoryData();
              }
          )
        ],
      ),
      body: _latest == null && !_isLoadingHistory
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text("기록이 없습니다.\nHA 센서를 확인하세요.\n(${_api.options.healthSensorPrefix})", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadCurrentData(), _loadHistoryData()]);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. 최신 데이터 카드 (가장 먼저 표시)
            if (_latest != null) _buildLatestCard(_latest!),

            const SizedBox(height: 24),
            const Text("최근 변화 (30일)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // 2. 그래프 (로딩 중이면 로딩 표시)
            _isLoadingHistory
                ? const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()))
                : _buildLineChart(),

            const SizedBox(height: 24),
            const Text("상세 기록", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // 3. 리스트
            _isLoadingHistory
                ? const SizedBox(height: 100, child: Center(child: Text("기록 불러오는 중...", style: TextStyle(color: Colors.grey))))
                : _buildHistoryList(),
          ],
        ),
      ),
    );
  }

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
                record.pulse != null && record.pulse! > 0 ? '${record.pulse}' : '-',
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
    // 차트 데이터가 없으면 빈 공간
    if (_history.isEmpty) return const SizedBox(height: 250, child: Center(child: Text("차트 데이터 없음")));

    final chartData = _history.take(15).toList().reversed.toList();

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