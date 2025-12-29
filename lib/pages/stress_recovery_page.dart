// lib/pages/stress_recovery_page.dart

import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import 'base_health_page.dart';
import 'sleep_detail_page.dart';
import 'heart_rate_detail_page.dart';
import 'steps_page.dart';
import '../data/recovery_score.dart' as rec;

// 🎨 테마 컬러
const Color kEnergyGood = Color(0xFF00E676);   // 최상 (85+)
const Color kEnergyMod = Color(0xFF29B6F6);    // 양호 (65+)
const Color kEnergyLow = Color(0xFFFF9100);    // 주의 (45+)
const Color kEnergyBad = Color(0xFFFF5252);    // 휴식 필요 (<45)
const Color kCardBg = Colors.white;
const Color kBgColor = Color(0xFFF0F4F8);

class StressRecoveryPage extends HealthStatefulPage {
  const StressRecoveryPage({super.key});

  @override
  State<StressRecoveryPage> createState() => _StressRecoveryPageState();
}

class _StressRecoveryPageState extends HealthState<StressRecoveryPage> {
  @override
  List<HealthDataType> get types => const [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
  ];

  bool _loading = true;
  rec.RecoveryScore? _scoreData;
  rec.NightRecoveryBaseline? _todayBaseline;
  rec.NightRecoveryRaw? _todayRaw;
  List<rec.NightRecoveryRaw> _history = [];

  int? _yesterdaySteps;
  int? _avgSteps7;

  @override
  void initState() {
    super.initState();
    authReady.then((_) => _load());
  }

  // ---------------- 데이터 로딩 ----------------

  double? _numVal(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue?.toDouble();
    return null;
  }

  Future<Duration?> _sleepTotalInWindow(DateTime s, DateTime e) async {
    try {
      final pts = await health.getHealthDataFromTypes(types: const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION], startTime: s, endTime: e);
      final asleep = pts.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
      final base = asleep.isNotEmpty ? asleep : pts.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();
      int minSum = 0;
      for (final p in base) {
        final d = (p.dateTo!.isAfter(e) ? e : p.dateTo!).difference(p.dateFrom!.isBefore(s) ? s : p.dateFrom!).inMinutes;
        if (d > 0) minSum += d;
      }
      return minSum > 0 ? Duration(minutes: minSum) : null;
    } catch (_) { return null; }
  }

  Future<double?> _avgOfType(DateTime s, DateTime e, HealthDataType t) async {
    try {
      final pts = await health.getHealthDataFromTypes(types: [t], startTime: s, endTime: e);
      final vals = pts.map((p) => _numVal(p.value)).whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    } catch (_) { return null; }
  }

  Future<int?> _sumSteps(DateTime s, DateTime e) async {
    try {
      final total = await health.getTotalStepsInInterval(s, e);
      return total;
    } catch (_) { return null; }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (!authorized) { setState(() => _loading = false); return; }

    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);

    // 1. 회복 데이터 (수면/심박) - ✅ 10일치로 통일
    final rawNights = <rec.NightRecoveryRaw>[];
    for (int i = 10; i >= 0; i--) {
      final anchor = today0.subtract(Duration(days: i));
      final s = anchor.subtract(const Duration(hours: 6));
      final e = anchor.add(const Duration(hours: 12));

      final sleep = await _sleepTotalInWindow(s, e);
      final hr = await _avgOfType(s, e, HealthDataType.HEART_RATE);

      if (sleep != null || hr != null) {
        rawNights.add(rec.NightRecoveryRaw(nightDate: anchor, hrMean: hr, sleepTotal: sleep));
      }
    }

    // 2. 활동량 데이터
    final yesterdayStart = today0.subtract(const Duration(days: 1));
    final yesterdayEnd = today0;
    final ySteps = await _sumSteps(yesterdayStart, yesterdayEnd);

    int stepSum = 0;
    int stepCount = 0;
    for (int i = 1; i <= 7; i++) {
      final d = today0.subtract(Duration(days: i));
      final s = await _sumSteps(d, d.add(const Duration(days: 1)));
      if (s != null) { stepSum += s; stepCount++; }
    }
    final avgSteps = stepCount > 0 ? (stepSum / stepCount).round() : null;

    if (rawNights.isNotEmpty) {
      // 3일~7일 윈도우 사용 (데이터 충분 시)
      final baselines = rec.computeNightBaselines(rawNights, minWindow: 3, maxWindow: 7);
      final score = rec.computeRecoveryFromNights(rawNights);

      setState(() {
        _scoreData = score;
        _todayRaw = rawNights.last;
        _todayBaseline = baselines.last;
        _history = rawNights;
        _yesterdaySteps = ySteps;
        _avgSteps7 = avgSteps;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  // ---------------- UI 빌더 ----------------

  // ✅ [수정됨] 색상 기준 (85 / 65 / 45)
  Color _getColor(int score) {
    if (score >= 85) return kEnergyGood;
    if (score >= 65) return kEnergyMod;
    if (score >= 45) return kEnergyLow;
    return kEnergyBad;
  }

  // ✅ [수정됨] 멘트 기준 (85 / 65 / 45)
  String _getSmartComment(int score) {
    final ySteps = _yesterdaySteps ?? 0;
    final avgSteps = _avgSteps7 ?? 1;
    final isHighActivity = ySteps > avgSteps * 1.2;

    if (score >= 85) {
      if (isHighActivity) return "어제 많이 움직였는데도 회복이 완벽해요! 체력이 정말 좋으시네요. 💪";
      return "컨디션 최고조! 오늘 같은 날 운동하면 효과가 좋아요. 🚀";
    }
    else if (score >= 65) {
      return "몸 상태가 안정적입니다. 평소대로 활동하셔도 좋습니다. 🙂";
    }
    else if (score >= 45) {
      if (isHighActivity) return "어제 활동량이 많아서 피로가 조금 쌓였네요. 오늘은 가볍게 보내세요. 🔋";
      return "에너지가 조금 부족해요. 무리한 활동보다는 휴식을 추천합니다.";
    }
    else {
      if (isHighActivity) return "어제 무리하셨군요! 몸이 회복할 시간이 필요합니다. 푹 쉬세요. 🛌";
      return "몸이 지쳤다는 신호입니다. 오늘은 충전에만 집중하세요. 🛑";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: const Text('오늘의 컨디션', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: kBgColor, elevation: 0, iconTheme: const IconThemeData(color: Colors.black87),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _scoreData == null
          ? const Center(child: Text("데이터가 충분하지 않습니다."))
          : RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final score = _scoreData!.score;
    final color = _getColor(score);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 1. 배터리 게이지
        Container(
          padding: const EdgeInsets.symmetric(vertical: 30),
          decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200, height: 200,
                    child: CircularProgressIndicator(value: score / 100, strokeWidth: 20, backgroundColor: Colors.grey[200], color: color, strokeCap: StrokeCap.round),
                  ),
                  Column(
                    children: [
                      const Icon(Icons.bolt_rounded, size: 40, color: Colors.grey),
                      Text("$score", style: TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: color, height: 1.0)),
                      const Text("점", style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_getSmartComment(score), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 2. 3단 비교 카드
        const Text("컨디션 분석 리포트", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        _ComparisonCard(
          title: "어제 활동량",
          icon: Icons.directions_walk,
          color: Colors.orange,
          current: _yesterdaySteps?.toDouble() ?? 0,
          baseline: _avgSteps7?.toDouble() ?? 0,
          unit: "걸음",
          isDuration: false,
          higherIsBetter: true,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StepsPage())),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(child: _ComparisonCard(
              title: "간밤 수면",
              icon: Icons.bedtime,
              color: Colors.indigo,
              current: _todayRaw?.sleepTotal?.inMinutes.toDouble() ?? 0,
              baseline: _todayBaseline?.sleepTotalBase?.inMinutes.toDouble() ?? 0,
              unit: "분",
              isDuration: true,
              higherIsBetter: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepDetailPage())),
            )),
            const SizedBox(width: 12),
            Expanded(child: _ComparisonCard(
              title: "수면 심박수",
              icon: Icons.favorite,
              color: Colors.red,
              current: _todayRaw?.hrMean ?? 0,
              baseline: _todayBaseline?.hrMeanBase ?? 0,
              unit: "bpm",
              isDuration: false,
              higherIsBetter: false,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeartRateDetailPage())),
            )),
          ],
        ),
        const SizedBox(height: 24),

        Text(
          "💡 팁: '어제 활동량'이 평소보다 훨씬 많은데 회복 점수가 낮다면,\n단순한 피로이니 푹 쉬면 금방 좋아집니다.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final String title; final IconData icon; final Color color; final double current; final double baseline; final String unit; final bool isDuration; final bool higherIsBetter; final VoidCallback? onTap;

  const _ComparisonCard({
    required this.title, required this.icon, required this.color, required this.current, required this.baseline, required this.unit, required this.isDuration, required this.higherIsBetter, this.onTap
  });

  @override
  Widget build(BuildContext context) {
    final diff = current - baseline;
    final percent = baseline > 0 ? (diff / baseline * 100) : 0.0;
    final isHigher = diff > 0;

    String statusLabel;
    Color statusColor;

    if (percent.abs() < 10) {
      statusLabel = "평소와 비슷";
      statusColor = Colors.grey;
    } else {
      if (higherIsBetter) {
        statusLabel = isHigher ? "평소보다 많음" : "평소보다 적음";
        statusColor = isHigher ? Colors.green : Colors.orange;
      } else {
        statusLabel = isHigher ? "평소보다 높음" : "평소보다 낮음";
        statusColor = isHigher ? Colors.orange : Colors.green;
      }
    }

    String fmt(double v) {
      if (isDuration) {
        final m = v.toInt();
        return "${m ~/ 60}h ${m % 60}m";
      }
      return v >= 1000 ? NumberFormat('#,###').format(v) : v.toStringAsFixed(0);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withOpacity(0.1))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey))]),
            const SizedBox(height: 12),
            Text(fmt(current), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text("평소 ${fmt(baseline)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
              ),
            )
          ],
        ),
      ),
    );
  }
}