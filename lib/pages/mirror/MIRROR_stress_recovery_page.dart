import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// API 및 설정
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';

// 페이지 이동
import 'mirror_steps_page.dart';
import 'MIRROR_sleep_detail_page.dart';
import 'MIRROR_heart_rate_detail_page.dart';

class MirrorStressRecoveryPage extends StatefulWidget {
  const MirrorStressRecoveryPage({super.key});

  @override
  State<MirrorStressRecoveryPage> createState() => _MirrorStressRecoveryPageState();
}

class _MirrorStressRecoveryPageState extends State<MirrorStressRecoveryPage> {
  late final HomeAssistantApi _api;
  bool _loading = true;

  // 데이터 상태 (초기값 0으로 설정하여 로딩 실패해도 UI 표시)
  int _recoveryScore = 0;
  String _comment = "데이터 분석 중...";
  Color _statusColor = Colors.grey;

  // 비교 데이터
  double _yesterdaySteps = 0;
  double _avgSteps = 0;

  double _lastSleepMin = 0;
  double _avgSleepMin = 0;

  double _lastHr = 0;
  double _avgHr = 0;

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

      final scoreId = 'sensor.recovery_score';
      final stepsId = '${prefix}daily_steps';
      final sleepId = '${prefix}sleep_duration';
      final hrId = '${prefix}heart_rate';

      // 1. 점수 가져오기
      final scoreState = await _api.getState(scoreId);
      int score = double.tryParse(scoreState.state)?.toInt() ?? 0;

      // 2. 히스토리 가져오기 (데이터 없어도 빈 리스트 반환됨 - 에러 안 남)
      final stepsHist = await _api.getHistory(stepsId, days: 7);
      final sleepHist = await _api.getHistory(sleepId, days: 7);
      final hrHist = await _api.getHistory(hrId, days: 7);

      // 3. 통계 계산
      final stepsData = _calcStats(stepsHist, isCumulative: true);
      final sleepData = _calcStats(sleepHist, isCumulative: true);
      final hrData = _calcStats(hrHist, isCumulative: false);

      // 4. 점수 보정 로직 (센서가 0일 경우 수동 계산)
      if (score == 0) {
        if (sleepData.current > 0) {
          if (hrData.current > 0) {
            // 수면 + 심박수 기반 계산
            score = ((sleepData.current / 480 * 60) + (100 - hrData.current) * 0.4).clamp(0, 100).toInt();
          } else {
            // 수면 시간만으로 계산 (심박수 데이터 없을 때)
            score = (sleepData.current / 480 * 100).clamp(0, 100).toInt();
          }
        }
      }

      // 5. 멘트 설정
      _analyzeScore(score, stepsData.current, stepsData.average);

      if (mounted) {
        setState(() {
          _recoveryScore = score;
          _yesterdaySteps = stepsData.current;
          _avgSteps = stepsData.average;
          _lastSleepMin = sleepData.current;
          _avgSleepMin = sleepData.average;
          _lastHr = hrData.current;
          _avgHr = hrData.average;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Recovery Load Error: $e");
      // 에러가 나도 로딩 상태 해제하여 UI 보여줌 (값은 0)
      if (mounted) setState(() => _loading = false);
    }
  }

  void _analyzeScore(int score, double currentSteps, double avgSteps) {
    if (score == 0) {
      _statusColor = Colors.grey;
      _comment = "데이터가 부족하여\n분석할 수 없습니다.";
      return;
    }

    if (score >= 85) {
      _statusColor = const Color(0xFF00E676);
      _comment = "컨디션 최고조! 🚀\n오늘 같은 날 운동하면 효과가 좋아요.";
    } else if (score >= 65) {
      _statusColor = const Color(0xFF29B6F6);
      _comment = "몸 상태가 안정적입니다. 🙂\n평소대로 활동하셔도 좋습니다.";
    } else if (score >= 45) {
      _statusColor = const Color(0xFFFF9100);
      if (currentSteps > avgSteps * 1.2) {
        _comment = "어제 활동량이 많았네요. 🔋\n오늘은 가볍게 보내세요.";
      } else {
        _comment = "에너지가 조금 부족해요.\n무리한 활동보다는 휴식을 추천합니다.";
      }
    } else {
      _statusColor = const Color(0xFFFF5252);
      _comment = "몸이 지쳤다는 신호입니다. 🛑\n오늘은 충전에만 집중하세요.";
    }
  }

  ({double current, double average}) _calcStats(List<Map<String, dynamic>> history, {required bool isCumulative}) {
    if (history.isEmpty) return (current: 0.0, average: 0.0);

    Map<String, double> dailyValues = {};

    for (var item in history) {
      final val = double.tryParse(item['state'].toString());
      final dateStr = item['last_changed'];
      if (val == null || dateStr == null) continue;

      final date = DateTime.parse(dateStr).toLocal();
      final key = DateFormat('yyyy-MM-dd').format(date);

      if (isCumulative) {
        if (!dailyValues.containsKey(key) || val > dailyValues[key]!) {
          dailyValues[key] = val;
        }
      } else {
        dailyValues[key] = val; // 마지막 값 (심박수 등)
      }
    }

    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    double current = 0;
    // 값이 오늘 없으면 어제 값이라도 사용 (미러는 보통 아침에 보니까)
    if (isCumulative) {
      current = dailyValues[todayKey] ?? dailyValues[yesterdayKey] ?? 0;
    } else {
      current = dailyValues[todayKey] ?? 0;
    }

    if (dailyValues.isEmpty) return (current: current, average: 0.0);
    double sum = dailyValues.values.reduce((a, b) => a + b);
    double avg = sum / dailyValues.length;

    return (current: current, average: avg);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 데이터가 없어도 절대 '데이터 부족' 흰 화면을 띄우지 않고, 그냥 0으로 채워진 UI를 보여줌
    return Scaffold(
      backgroundColor: Colors.black, // 배경 검정 고정
      appBar: AppBar(
        title: const Text('오늘의 컨디션', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
        actions: [IconButton(icon: const Icon(Icons.refresh, size: 30), onPressed: _loadData)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(30),
          children: [
            _buildScoreCard(),
            const SizedBox(height: 40),

            const Text("컨디션 분석 리포트", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),

            _MirrorComparisonCard(
              title: "활동량",
              icon: Icons.directions_walk,
              color: Colors.orange,
              current: _yesterdaySteps,
              baseline: _avgSteps,
              unit: "걸음",
              isDuration: false,
              higherIsBetter: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorStepsPage())),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: _MirrorComparisonCard(
                  title: "수면",
                  icon: Icons.bedtime,
                  color: Colors.indigoAccent,
                  current: _lastSleepMin,
                  baseline: _avgSleepMin,
                  unit: "분",
                  isDuration: true,
                  higherIsBetter: true,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorSleepDetailPage())),
                )),
                const SizedBox(width: 20),
                Expanded(child: _MirrorComparisonCard(
                  title: "심박수",
                  icon: Icons.favorite,
                  color: Colors.redAccent,
                  current: _lastHr,
                  baseline: _avgHr,
                  unit: "bpm",
                  isDuration: false,
                  higherIsBetter: false,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorHeartRateDetailPage())),
                )),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 280, height: 280,
                child: CircularProgressIndicator(
                    value: _recoveryScore > 0 ? _recoveryScore / 100 : 0, // 0이면 0
                    strokeWidth: 22,
                    backgroundColor: Colors.white10,
                    color: _statusColor,
                    strokeCap: StrokeCap.round
                ),
              ),
              Column(
                children: [
                  const Icon(Icons.bolt_rounded, size: 50, color: Colors.grey),
                  Text("$_recoveryScore", style: TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: _statusColor, height: 1.0)),
                  const Text("점", style: TextStyle(fontSize: 20, color: Colors.grey)),
                ],
              )
            ],
          ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
                _comment,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, height: 1.5)
            ),
          ),
        ],
      ),
    );
  }
}

class _MirrorComparisonCard extends StatelessWidget {
  final String title; final IconData icon; final Color color; final double current; final double baseline; final String unit; final bool isDuration; final bool higherIsBetter; final VoidCallback? onTap;

  const _MirrorComparisonCard({
    required this.title, required this.icon, required this.color, required this.current, required this.baseline, required this.unit, required this.isDuration, required this.higherIsBetter, this.onTap
  });

  @override
  Widget build(BuildContext context) {
    final diff = current - baseline;
    final percent = baseline > 0 ? (diff / baseline * 100) : 0.0;
    final isHigher = diff > 0;

    String statusLabel = "데이터 없음";
    Color statusColor = Colors.grey;

    if (current > 0 && baseline > 0) {
      if (percent.abs() < 10) {
        statusLabel = "평소와 비슷";
        statusColor = Colors.grey;
      } else {
        if (higherIsBetter) {
          statusLabel = isHigher ? "평소보다 많음" : "평소보다 적음";
          statusColor = isHigher ? Colors.greenAccent : Colors.orangeAccent;
        } else {
          statusLabel = isHigher ? "평소보다 높음" : "평소보다 낮음";
          statusColor = isHigher ? Colors.orangeAccent : Colors.greenAccent;
        }
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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 28, color: color), const SizedBox(width: 12), Text(title, style: const TextStyle(fontSize: 18, color: Colors.grey))]),
            const SizedBox(height: 16),
            Text(fmt(current), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text("평소 ${fmt(baseline)}", style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: statusColor),
              ),
            )
          ],
        ),
      ),
    );
  }
}