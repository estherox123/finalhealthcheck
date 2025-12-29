import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';

import 'base_health_page.dart';

// 🎨 컬러 팔레트 (심박수 테마)
const Color kHeartColor = Color(0xFFFF5252); // 메인 레드
const Color kHeartBgColor = Color(0xFFFFEBEE); // 연한 핑크 배경
const Color kGridLineColor = Color(0xFFEEEEEE); // 차트 그리드
const Color kBgColor = Color(0xFFF5F7FA); // 전체 배경

class HeartRateDetailPage extends HealthStatefulPage {
  const HeartRateDetailPage({super.key});

  @override
  State<HeartRateDetailPage> createState() => _HeartRateDetailPageState();
}

class _HeartRateDetailPageState extends HealthState<HeartRateDetailPage> {
  @override
  List<HealthDataType> get types => const [HealthDataType.HEART_RATE];

  bool _loading = true;
  _HrVm? _vm;

  @override
  void initState() {
    super.initState();
    authReady.then((_) {
      if (!mounted) return;
      _load();
    });
  }

  // ---------------- 데이터 로딩 ----------------
  double? _numVal(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue?.toDouble();
    return null;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!authorized) return;

      final now = DateTime.now();
      // "오늘" 기준 (00:00 ~ 현재)
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = now;

      // 1. 오늘 심박수 상세 데이터 (라인 차트용)
      final hrPoints = await health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE],
        startTime: todayStart,
        endTime: todayEnd,
      );

      final samples = <_HrPoint>[];
      double? minHr, maxHr, sumHr;
      int count = 0;

      for (final p in hrPoints) {
        final v = _numVal(p.value);
        if (v == null) continue;
        final t = p.dateFrom; // dateFrom 기준

        final vD = v.toDouble();
        samples.add(_HrPoint(time: t, bpm: vD));

        if (minHr == null || vD < minHr) minHr = vD;
        if (maxHr == null || vD > maxHr) maxHr = vD;
        sumHr = (sumHr ?? 0) + vD;
        count++;
      }

      // 시간순 정렬
      samples.sort((a, b) => a.time.compareTo(b.time));

      final avgHr = (count > 0 && sumHr != null) ? (sumHr / count) : null;

      // 2. 최근 7일 평균 (막대 차트용)
      final last7Avg = <DateTime, double>{};
      for (int i = 6; i >= 0; i--) {
        final d = todayStart.subtract(Duration(days: i));
        final s = d;
        final e = d.add(const Duration(days: 1)); // 하루 전체

        final pts = await health.getHealthDataFromTypes(
          types: const [HealthDataType.HEART_RATE],
          startTime: s, endTime: e,
        );

        double daySum = 0;
        int dayCount = 0;
        for (final p in pts) {
          final v = _numVal(p.value);
          if (v != null) {
            daySum += v;
            dayCount++;
          }
        }
        if (dayCount > 0) {
          last7Avg[d] = daySum / dayCount;
        }
      }

      _vm = _HrVm(
        periodStart: todayStart,
        periodEnd: todayEnd,
        avgHr: avgHr,
        minHr: minHr,
        maxHr: maxHr,
        samples: samples,
        last7Avg: last7Avg,
      );

    } catch (e) {
      debugPrint("HR Load Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------- UI 빌더 ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: const Text('심박수', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: kBgColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vm == null || _vm!.samples.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(onRefresh: _load, child: _buildDashboard()),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.monitor_heart_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 16),
          Text("오늘 측정된 심박수가 없습니다.\n워치를 착용하고 계신가요?", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final vm = _vm!;
    final avg = vm.avgHr?.round() ?? 0;

    // 상태 분석 텍스트
    String statusText = "정상 범위";
    Color statusColor = Colors.green;
    if (avg > 100) { statusText = "높음"; statusColor = Colors.orange; }
    else if (avg < 50) { statusText = "낮음 (운동선수?)"; statusColor = Colors.blue; }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 1. 메인 심박수 카드 (심장 아이콘 + 큰 숫자)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("오늘 평균 심박수", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(statusText, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kHeartBgColor, shape: BoxShape.circle),
                    child: const Icon(Icons.favorite_rounded, color: kHeartColor, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text("$avg", style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: Colors.black87)),
                  const SizedBox(width: 8),
                  const Text("bpm", style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 2. 미니 정보 그리드 (최저/최고)
        Row(
          children: [
            _MiniInfoCard(title: "최저 심박수", value: "${vm.minHr?.round() ?? '-'}", unit: "bpm", icon: Icons.arrow_downward_rounded, color: Colors.blue),
            const SizedBox(width: 12),
            _MiniInfoCard(title: "최고 심박수", value: "${vm.maxHr?.round() ?? '-'}", unit: "bpm", icon: Icons.arrow_upward_rounded, color: Colors.red),
          ],
        ),
        const SizedBox(height: 24),

        // 3. 오늘 심박수 흐름 (그라데이션 라인 차트)
        const Text("오늘의 흐름", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text("그래프를 터치하면 상세 시간을 볼 수 있어요.", style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        _InteractiveLineChart(vm: vm),
        const SizedBox(height: 30),

        // 4. 주간 차트
        const Text("최근 7일 트렌드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _WeeklyBarChart(vm: vm),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ---------------- 위젯: 미니 정보 카드 ----------------
class _MiniInfoCard extends StatelessWidget {
  final String title; final String value; final String unit; final IconData icon; final Color color;
  const _MiniInfoCard({required this.title, required this.value, required this.unit, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13))]),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ---------------- 위젯: 인터랙티브 라인 차트 (그라데이션 포함) ----------------
class _InteractiveLineChart extends StatelessWidget {
  final _HrVm vm;
  const _InteractiveLineChart({required this.vm});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    // 데이터가 너무 많으면 끊길 수 있으니 적절히 샘플링하거나 그대로 표시 (여기선 그대로)
    final startTime = vm.periodStart;

    for (var p in vm.samples) {
      final minutes = p.time.difference(startTime).inMinutes.toDouble();
      spots.add(FlSpot(minutes, p.bpm));
    }

    // Y축 범위 계산
    double minY = 40, maxY = 150;
    if (vm.minHr != null) minY = (vm.minHr! - 10).clamp(0, 200);
    if (vm.maxHr != null) maxY = (vm.maxHr! + 10).clamp(50, 220);

    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(16, 24, 24, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: LineChart(
        LineChartData(
          minY: minY, maxY: maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 20, getDrawingHorizontalLine: (_) => FlLine(color: kGridLineColor, strokeWidth: 1)),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (val, meta) {
              if (val % 20 == 0) return Text("${val.toInt()}", style: const TextStyle(color: Colors.grey, fontSize: 10));
              return const SizedBox();
            })),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 60 * 6, getTitlesWidget: (val, meta) { // 6시간 간격
              final d = startTime.add(Duration(minutes: val.toInt()));
              return Padding(padding: const EdgeInsets.only(top: 8), child: Text(DateFormat('a h시', 'ko').format(d), style: const TextStyle(color: Colors.grey, fontSize: 10)));
            })),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: kHeartColor,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kHeartColor.withOpacity(0.3), kHeartColor.withOpacity(0.0)])),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final d = startTime.add(Duration(minutes: spot.x.toInt()));
                  return LineTooltipItem(
                    "${DateFormat('a h:mm', 'ko').format(d)}\n",
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    children: [TextSpan(text: "${spot.y.toInt()} bpm", style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.w800))],
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- 위젯: 주간 바 차트 ----------------
class _WeeklyBarChart extends StatelessWidget {
  final _HrVm vm;
  const _WeeklyBarChart({required this.vm});

  @override
  Widget build(BuildContext context) {
    final entries = vm.last7Avg.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    // 최대값 계산
    double maxVal = 0;
    for (var e in entries) if (e.value > maxVal) maxVal = e.value;
    final maxY = (maxVal < 100 ? 100.0 : maxVal * 1.2);

    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: entries.asMap().entries.map((e) {
            final idx = e.key;
            final isToday = idx == entries.length - 1;
            return BarChartGroupData(
              x: idx,
              barRods: [BarChartRodData(toY: e.value.value, color: isToday ? kHeartColor : kHeartColor.withOpacity(0.3), width: 14, borderRadius: BorderRadius.circular(4))],
            );
          }).toList(),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (val, meta) {
              if (val > 0 && val % 50 == 0) return Text("${val.toInt()}", style: const TextStyle(color: Colors.grey, fontSize: 10));
              return const SizedBox();
            })),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) {
              final idx = val.toInt();
              if (idx >= 0 && idx < entries.length) return Padding(padding: const EdgeInsets.only(top: 8), child: Text(DateFormat('E', 'ko').format(entries[idx].key), style: const TextStyle(fontSize: 11, color: Colors.grey)));
              return const SizedBox();
            })),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 50),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x.toInt();
                final date = entries[idx].key;
                return BarTooltipItem(
                  '${DateFormat('MM/dd (E)', 'ko').format(date)}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  children: [TextSpan(text: "${rod.toY.toInt()} bpm", style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.w800))],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- ViewModel ----------------
class _HrVm {
  final DateTime periodStart; final DateTime periodEnd;
  final double? avgHr; final double? minHr; final double? maxHr;
  final List<_HrPoint> samples;
  final Map<DateTime, double> last7Avg;

  _HrVm({required this.periodStart, required this.periodEnd, required this.avgHr, required this.minHr, required this.maxHr, required this.samples, required this.last7Avg});
}

class _HrPoint {
  final DateTime time; final double bpm;
  _HrPoint({required this.time, required this.bpm});
}