import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui' as ui;
import 'base_health_page.dart';

// 🎨 컬러 팔레트
const Color kDeepSleepColor = Color(0xFF1A237E); // 깊은 잠 (진한 남색)
const Color kLightSleepColor = Color(0xFF5C6BC0); // 얕은 잠 (부드러운 파랑)
const Color kRemSleepColor = Color(0xFF26C6DA);   // 렘 수면 (청록색)
const Color kWakeColor = Color(0xFFFFB74D);       // 깸 (주황색)
const Color kCardBg = Colors.white;
const Color kBgColor = Color(0xFFF5F7FA);

class SleepDetailPage extends HealthStatefulPage {
  const SleepDetailPage({super.key});

  @override
  State<SleepDetailPage> createState() => _SleepDetailPageState();
}

class _SleepDetailPageState extends HealthState<SleepDetailPage> {
  @override
  List<HealthDataType> get types => const [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
  ];

  bool _loading = true;
  _SleepVm? _vm;

  @override
  void initState() {
    super.initState();
    authReady.then((_) {
      if (!mounted) return;
      _load();
    });
  }

  // ---------------- 데이터 로딩 ----------------
  Duration _clampedDuration(DateTime? from, DateTime? to, DateTime winStart, DateTime winEnd) {
    if (from == null || to == null) return Duration.zero;
    final s = from.isBefore(winStart) ? winStart : from;
    final e = to.isAfter(winEnd) ? winEnd : to;
    if (!e.isAfter(s)) return Duration.zero;
    return e.difference(s);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!authorized) return;

      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);
      final winStart = today0.subtract(const Duration(hours: 6));
      final winEnd = today0.add(const Duration(hours: 12));

      // 1. 상세 수면 단계
      final stagePoints = await health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_AWAKE, HealthDataType.SLEEP_REM, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_DEEP],
        startTime: winStart, endTime: winEnd,
      );

      final stageDurations = <SleepStageType, Duration>{
        SleepStageType.deep: Duration.zero, SleepStageType.light: Duration.zero,
        SleepStageType.rem: Duration.zero, SleepStageType.wake: Duration.zero,
      };
      final segments = <SleepStageSegment>[];

      SleepStageType? mapType(HealthDataType t) {
        if (t == HealthDataType.SLEEP_DEEP) return SleepStageType.deep;
        if (t == HealthDataType.SLEEP_LIGHT) return SleepStageType.light;
        if (t == HealthDataType.SLEEP_REM) return SleepStageType.rem;
        if (t == HealthDataType.SLEEP_AWAKE) return SleepStageType.wake;
        return null;
      }

      for (final p in stagePoints) {
        final stg = mapType(p.type);
        if (stg == null) continue;
        final dur = _clampedDuration(p.dateFrom, p.dateTo, winStart, winEnd);
        if (dur <= Duration.zero) continue;

        stageDurations[stg] = stageDurations[stg]! + dur;
        segments.add(SleepStageSegment(
          start: p.dateFrom!.isBefore(winStart) ? winStart : p.dateFrom!,
          end: p.dateTo!.isAfter(winEnd) ? winEnd : p.dateTo!,
          stage: stg,
        ));
      }

      Duration totalAsleep = stageDurations[SleepStageType.deep]! + stageDurations[SleepStageType.light]! + stageDurations[SleepStageType.rem]!;
      Duration totalWake = stageDurations[SleepStageType.wake]!;

      // 워치 상세 데이터 없으면 Session fallback
      if (totalAsleep.inMinutes == 0) {
        final sessions = await health.getHealthDataFromTypes(
            types: const [HealthDataType.SLEEP_SESSION], startTime: winStart, endTime: winEnd);
        for (final p in sessions) totalAsleep += _clampedDuration(p.dateFrom, p.dateTo, winStart, winEnd);
      }

      // 2. 주간 데이터
      final last7 = <DateTime, Duration>{};
      for (int i = 6; i >= 0; i--) {
        final anchor = today0.subtract(Duration(days: i));
        final s = anchor.subtract(const Duration(hours: 6));
        final e = anchor.add(const Duration(hours: 12));
        final sessions = await health.getHealthDataFromTypes(types: const [HealthDataType.SLEEP_SESSION, HealthDataType.SLEEP_ASLEEP], startTime: s, endTime: e);
        Duration sleepSum = Duration.zero;
        for (final p in sessions) {
          if (p.type != HealthDataType.SLEEP_AWAKE) sleepSum += _clampedDuration(p.dateFrom, p.dateTo, s, e);
        }
        last7[anchor] = sleepSum;
      }

      _vm = _SleepVm(
        nightStart: winStart, nightEnd: winEnd,
        totalAsleep: totalAsleep, totalWake: totalWake,
        stageDurations: stageDurations,
        segments: segments..sort((a, b) => a.start.compareTo(b.start)),
        last7Nights: last7,
      );

    } catch (e) {
      debugPrint("Sleep Load Error: $e");
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
        title: const Text('수면 분석', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: kBgColor, elevation: 0, iconTheme: const IconThemeData(color: Colors.black87),
        actions: [IconButton(icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vm == null || _vm!.totalAsleep.inMinutes == 0
          ? const Center(child: Text("수면 기록이 없습니다."))
          : RefreshIndicator(onRefresh: _load, child: _buildDashboard()),
    );
  }

  Widget _buildDashboard() {
    final vm = _vm!;
    final totalMin = vm.totalAsleep.inMinutes;
    final score = (totalMin / 480.0 * 100).clamp(0, 100).toInt();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 1. 점수 카드
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Column(
            children: [
              Text("오늘의 수면 점수", style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text("$score", style: const TextStyle(color: kDeepSleepColor, fontSize: 56, fontWeight: FontWeight.w800)),
                  const Text("점", style: TextStyle(color: Colors.grey, fontSize: 20)),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text("총 $h시간 $m분 수면", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 2. 수면 비율 바
        const Text("수면 구성 비율", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text("색상 바를 누르면 상세 시간이 보입니다.", style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        _buildStageRatioBar(vm),
        const SizedBox(height: 24),

        // 3. 상세 그리드
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.6, mainAxisSpacing: 12, crossAxisSpacing: 12,
          children: [
            _DetailCard(title: "깊은 수면", duration: vm.stageDurations[SleepStageType.deep]!, color: kDeepSleepColor, icon: Icons.bedtime),
            _DetailCard(title: "렘 수면", duration: vm.stageDurations[SleepStageType.rem]!, color: kRemSleepColor, icon: Icons.psychology),
            _DetailCard(title: "얕은 수면", duration: vm.stageDurations[SleepStageType.light]!, color: kLightSleepColor, icon: Icons.nights_stay),
            _DetailCard(title: "깨어있음", duration: vm.totalWake, color: kWakeColor, icon: Icons.wb_sunny),
          ],
        ),
        const SizedBox(height: 30),

        // 4. 히프노그램
        if (vm.segments.isNotEmpty) ...[
          Row(children: const [Icon(Icons.auto_graph, color: kDeepSleepColor), SizedBox(width: 8), Text("수면 패턴 타임라인", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 8),
          Container(
            height: 240,
            padding: const EdgeInsets.fromLTRB(12, 30, 12, 20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
            child: SleepTimelineChart(segments: vm.segments),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _LegendItem(color: kWakeColor, label: "깸"), const SizedBox(width: 12),
            _LegendItem(color: kRemSleepColor, label: "렘"), const SizedBox(width: 12),
            _LegendItem(color: kLightSleepColor, label: "얕음"), const SizedBox(width: 12),
            _LegendItem(color: kDeepSleepColor, label: "깊음"),
          ]),
          const SizedBox(height: 40),
        ],

        // 5. 주간 차트 (개선됨 ✅)
        const Text("최근 7일 트렌드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _WeeklyChart(vm: vm),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStageRatioBar(_SleepVm vm) {
    final deep = vm.stageDurations[SleepStageType.deep]?.inMinutes ?? 0;
    final light = vm.stageDurations[SleepStageType.light]?.inMinutes ?? 0;
    final rem = vm.stageDurations[SleepStageType.rem]?.inMinutes ?? 0;
    final wake = vm.totalWake.inMinutes;
    final total = deep + light + rem + wake;

    if (total == 0) return const SizedBox();

    Widget segment(int minutes, Color color, String label) {
      if (minutes <= 0) return const SizedBox();
      final h = minutes ~/ 60;
      final m = minutes % 60;
      final timeStr = h > 0 ? "${h}시간 ${m}분" : "${m}분";

      return Expanded(
        flex: minutes,
        child: Tooltip(
          message: "$label: $timeStr",
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 3),
          padding: const EdgeInsets.all(12),
          textStyle: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
          child: Container(color: color),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            segment(deep, kDeepSleepColor, "깊은 수면"),
            segment(light, kLightSleepColor, "얕은 수면"),
            segment(rem, kRemSleepColor, "렘 수면"),
            segment(wake, kWakeColor, "깨어있음"),
          ],
        ),
      ),
    );
  }
}

// ---------------- 히프노그램 차트 ----------------
class SleepTimelineChart extends StatefulWidget {
  final List<SleepStageSegment> segments;
  const SleepTimelineChart({super.key, required this.segments});

  @override
  State<SleepTimelineChart> createState() => _SleepTimelineChartState();
}

class _SleepTimelineChartState extends State<SleepTimelineChart> {
  SleepStageSegment? _selectedSegment;
  Offset? _touchPosition;

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) return const Center(child: Text("데이터 없음"));

    final sorted = List<SleepStageSegment>.from(widget.segments)..sort((a, b) => a.start.compareTo(b.start));
    final start = sorted.first.start;
    final end = sorted.last.end;
    final totalMinutes = end.difference(start).inMinutes;

    if (totalMinutes <= 0) return const SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return GestureDetector(
          onPanStart: (details) => _handleTouch(details.localPosition, w, sorted, start, totalMinutes),
          onPanUpdate: (details) => _handleTouch(details.localPosition, w, sorted, start, totalMinutes),
          onTapDown: (details) => _handleTouch(details.localPosition, w, sorted, start, totalMinutes),
          onTapUp: (_) => setState(() => _selectedSegment = null),
          onPanEnd: (_) => setState(() => _selectedSegment = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(w, h),
                painter: _ImprovedHypnogramPainter(segments: sorted, startTime: start, totalMinutes: totalMinutes),
              ),
              if (_selectedSegment != null && _touchPosition != null)
                Positioned(
                  left: (_touchPosition!.dx - 70).clamp(0.0, w - 140.0),
                  top: -40,
                  child: _buildTooltip(_selectedSegment!),
                ),
              if (_selectedSegment != null && _touchPosition != null)
                Positioned(left: _touchPosition!.dx, top: 0, bottom: 0, child: Container(width: 2, color: Colors.black12)),
            ],
          ),
        );
      },
    );
  }

  void _handleTouch(Offset localPos, double width, List<SleepStageSegment> segments, DateTime start, int totalMinutes) {
    final dx = localPos.dx.clamp(0.0, width);
    final ratio = dx / width;
    final minutesFromStart = (totalMinutes * ratio).round();
    final touchTime = start.add(Duration(minutes: minutesFromStart));

    SleepStageSegment? found;
    for (final seg in segments) {
      if (touchTime.isAfter(seg.start) && touchTime.isBefore(seg.end)) { found = seg; break; }
      if (touchTime.isAtSameMomentAs(seg.start) || touchTime.isAtSameMomentAs(seg.end)) { found = seg; break; }
    }
    setState(() { _selectedSegment = found; _touchPosition = Offset(dx, localPos.dy); });
  }

  Widget _buildTooltip(SleepStageSegment seg) {
    String label(SleepStageType t) => t == SleepStageType.deep ? "깊음" : (t == SleepStageType.light ? "얕음" : (t == SleepStageType.rem ? "렘" : "깸"));
    Color color(SleepStageType t) => t == SleepStageType.deep ? kDeepSleepColor : (t == SleepStageType.light ? kLightSleepColor : (t == SleepStageType.rem ? kRemSleepColor : kWakeColor));
    final startStr = DateFormat('HH:mm').format(seg.start);
    final endStr = DateFormat('HH:mm').format(seg.end);

    return Material(
      elevation: 4, borderRadius: BorderRadius.circular(8), color: Colors.black87,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color(seg.stage), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text("${label(seg.stage)}: $startStr ~ $endStr", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _ImprovedHypnogramPainter extends CustomPainter {
  final List<SleepStageSegment> segments;
  final DateTime startTime;
  final int totalMinutes;

  _ImprovedHypnogramPainter({required this.segments, required this.startTime, required this.totalMinutes});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final yWake = h * 0.1; final yRem = h * 0.35; final yLight = h * 0.6; final yDeep = h * 0.85;

    double getY(SleepStageType type) {
      if (type == SleepStageType.wake) return yWake;
      if (type == SleepStageType.rem) return yRem;
      if (type == SleepStageType.light) return yLight;
      return yDeep;
    }
    Color getColor(SleepStageType type) {
      if (type == SleepStageType.wake) return kWakeColor;
      if (type == SleepStageType.rem) return kRemSleepColor;
      if (type == SleepStageType.light) return kLightSleepColor;
      return kDeepSleepColor;
    }

    final gridPaint = Paint()..color = Colors.grey.withOpacity(0.1)..strokeWidth = 1;
    for (final y in [yWake, yRem, yLight, yDeep]) canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);

    final barPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = 8.0;
    final connectPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0..color = Colors.grey.withOpacity(0.2);

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final startMin = seg.start.difference(startTime).inMinutes;
      final endMin = seg.end.difference(startTime).inMinutes;
      final x1 = (startMin / totalMinutes) * w;
      final x2 = (endMin / totalMinutes) * w;
      final y = getY(seg.stage);

      barPaint.color = getColor(seg.stage);
      if (x2 - x1 < 2) canvas.drawLine(Offset(x1, y), Offset(x1 + 2, y), barPaint);
      else canvas.drawLine(Offset(x1, y), Offset(x2, y), barPaint);

      if (i < segments.length - 1) {
        final nextSeg = segments[i+1];
        canvas.drawLine(Offset(x2, y), Offset(x2, getY(nextSeg.stage)), connectPaint);
      }
    }
    final textStyle = const TextStyle(color: Colors.grey, fontSize: 10);
    _drawText(canvas, DateFormat('HH:mm').format(startTime), Offset(0, h - 15), textStyle);
    _drawText(canvas, DateFormat('HH:mm').format(segments.last.end), Offset(w - 30, h - 15), textStyle);
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: ui.TextDirection.ltr);
    tp.layout(); tp.paint(canvas, pos);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---------------- ✅ [업그레이드] 주간 차트 (Y축 라벨 + 툴팁 개선) ----------------

class _WeeklyChart extends StatelessWidget {
  final _SleepVm vm;
  const _WeeklyChart({required this.vm});

  @override
  Widget build(BuildContext context) {
    final entries = vm.last7Nights.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    // Y축 최대값 계산 (여유분 포함)
    double maxHours = 0;
    for (var e in entries) {
      if (e.value.inMinutes > maxHours * 60) maxHours = e.value.inMinutes / 60.0;
    }
    final maxY = (maxHours < 8 ? 8.0 : maxHours * 1.2); // 최소 8시간은 확보

    return Container(
      height: 240, // 높이 약간 증가
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20)),
      child: BarChart(
        BarChartData(
          barGroups: entries.asMap().entries.map((e) {
            final idx = e.key;
            final isToday = idx == entries.length - 1;
            final hours = e.value.value.inMinutes / 60.0;
            return BarChartGroupData(
              x: idx,
              barRods: [BarChartRodData(toY: hours, color: isToday ? kDeepSleepColor : kDeepSleepColor.withOpacity(0.3), width: 14, borderRadius: BorderRadius.circular(4))],
            );
          }).toList(),
          maxY: maxY,
          titlesData: FlTitlesData(
            // ✅ 왼쪽 Y축 라벨 추가
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30, // 공간 확보
                getTitlesWidget: (val, meta) {
                  if (val == 0) return const SizedBox();
                  return Text("${val.toInt()}h", style: const TextStyle(color: Colors.grey, fontSize: 10));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) {
              final idx = val.toInt();
              if (idx >= 0 && idx < entries.length) return Padding(padding: const EdgeInsets.only(top: 8), child: Text(DateFormat('E', 'ko').format(entries[idx].key), style: const TextStyle(fontSize: 11, color: Colors.grey)));
              return const SizedBox();
            })),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 2), // 2시간 단위 가로선
          borderData: FlBorderData(show: false),
          // ✅ 툴팁 개선
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x.toInt();
                final date = entries[idx].key;
                final totalMin = entries[idx].value.inMinutes;
                final h = totalMin ~/ 60;
                final m = totalMin % 60;

                return BarTooltipItem(
                  '${DateFormat('MM/dd (E)', 'ko').format(date)}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  children: [
                    TextSpan(
                      text: '$h시간 $m분',
                      style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- 기타 (기존 유지) ----------------
class _DetailCard extends StatelessWidget {
  final String title; final Duration duration; final Color color; final IconData icon;
  const _DetailCard({required this.title, required this.duration, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    final h = duration.inMinutes ~/ 60; final m = duration.inMinutes % 60;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Text(title, style: TextStyle(color: Colors.grey[700], fontSize: 13))]), const Spacer(), Text("${h}시간 ${m}분", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87))]),
    );
  }
}
class _LegendItem extends StatelessWidget {
  final Color color; final String label;
  const _LegendItem({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))]);
  }
}
class _SleepVm {
  final DateTime nightStart; final DateTime nightEnd;
  final Duration totalAsleep; final Duration totalWake;
  final Map<SleepStageType, Duration> stageDurations;
  final List<SleepStageSegment> segments;
  final Map<DateTime, Duration> last7Nights;
  _SleepVm({required this.nightStart, required this.nightEnd, required this.totalAsleep, required this.totalWake, required this.stageDurations, required this.segments, required this.last7Nights});
}
enum SleepStageType { wake, light, deep, rem }
class SleepStageSegment {
  final DateTime start; final DateTime end; final SleepStageType stage;
  SleepStageSegment({required this.start, required this.end, required this.stage});
}