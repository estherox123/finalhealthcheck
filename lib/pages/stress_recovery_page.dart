import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

/// 스트레스/회복 요약 페이지
/// - 입력: HRV(RMSSD, 야간), Heart Rate(야간), Respiratory Rate(야간), Body Temperature(야간)
/// - 기준선: 최근 3일(어젯밤 제외) 개인 기준선과 비교
/// - 출력: 총점(0~100) + 4단계 상태(회복↑/양호/주의/휴식필요) + 간단 권장 행동
class StressRecoveryPage extends StatefulWidget {
  const StressRecoveryPage({super.key});
  @override
  State<StressRecoveryPage> createState() => _StressRecoveryPageState();
}

class _StressRecoveryPageState extends State<StressRecoveryPage> {
  final Health _health = Health();

  bool _loading = true;
  String? _error;

  // 현재(어젯밤) 값
  double? _hrvNow;
  double? _hrNow;
  double? _respNow;
  double? _tempNow;

  // 기준선(최근 14일 중앙값)
  double? _hrvBase;
  double? _hrBase;
  double? _respBase;
  double? _tempBase;

  // 결과
  int? _score;     // 0~100
  String? _stage;  // 회복↑ / 양호 / 주의 / 휴식 필요
  Color _color = Colors.grey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ----------------- 메인 로드 -----------------
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _score = null;
      _stage = null;
    });

    try {
      // 1) 권한
      final ok = await _health.requestAuthorization(
        const [
          HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
          HealthDataType.HEART_RATE,
          HealthDataType.RESPIRATORY_RATE,
          HealthDataType.BODY_TEMPERATURE,
        ],
        permissions: const [
          HealthDataAccess.READ,
          HealthDataAccess.READ,
          HealthDataAccess.READ,
          HealthDataAccess.READ,
        ],
      );
      if (!ok) {
        setState(() {
          _error = '필요한 권한이 없어 데이터를 읽을 수 없어요. Health Connect에서 권한을 허용해주세요.';
          _loading = false;
        });
        return;
      }

      // 2) 시간 창 정의: 야간 = 전일 18:00 ~ 당일 12:00
      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);
      final winStartNow = today0.subtract(const Duration(hours: 6));
      final winEndNow = today0.add(const Duration(hours: 12));

      // 3) 현재(어젯밤) 평균
      _hrvNow  = await _avgOf(winStartNow, winEndNow, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
      _hrNow   = await _avgOf(winStartNow, winEndNow, HealthDataType.HEART_RATE);
      _respNow = await _avgOf(winStartNow, winEndNow, HealthDataType.RESPIRATORY_RATE);
      _tempNow = await _avgOf(winStartNow, winEndNow, HealthDataType.BODY_TEMPERATURE);

      // 4) 기준선(최근 3일, 어젯밤 제외) 중앙값
      final base = await _buildBaselines(today0, days: 3);
      _hrvBase  = base['HRV'] ?? _hrvNow;
      _hrBase   = base['HR']  ?? _hrNow;
      _respBase = base['RESP']?? _respNow;
      _tempBase = base['BT']  ?? _tempNow;

      // 5) 점수 산출
      final score = _computeScore(
        hrvNow: _hrvNow,  hrvBase: _hrvBase,
        hrNow:  _hrNow,   hrBase:  _hrBase,
        respNow:_respNow, respBase:_respBase,
        btNow:  _tempNow, btBase:  _tempBase,
      );

      final (stage, color) = _stageFromScore(score);
      if (!mounted) return;
      setState(() {
        _score = score.round().clamp(0, 100);
        _stage = stage;
        _color = color;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '데이터 로드 중 오류가 발생했습니다: $e';
        _loading = false;
      });
    }
  }

  // ----------------- 데이터 수집 유틸 -----------------
  Future<double?> _avgOf(DateTime s, DateTime e, HealthDataType t) async {
    try {
      final pts = await _health.getHealthDataFromTypes(
        types: [t], startTime: s, endTime: e,
      );
      if (pts.isEmpty) return null;
      final values = <double>[];
      for (final p in pts) {
        final v = _toDouble(p.value);
        if (v != null && v.isFinite) values.add(v);
      }
      if (values.isEmpty) return null;
      return values.reduce((a,b)=>a+b) / values.length;
    } catch (_) {
      return null;
    }
  }

  // days일 동안(어젯밤 제외) 야간 창 중앙값
  Future<Map<String,double?>> _buildBaselines(DateTime today0, {int days = 3}) async {
    final hrv = <double>[], hr = <double>[], resp = <double>[], bt = <double>[];
    for (int i = 1; i <= days + 1; i++) { // i=1: 어제, i=2..days+1: 그 이전
      final anchor = today0.subtract(Duration(days: i));
      final s = anchor.subtract(const Duration(hours: 6));
      final e = anchor.add(const Duration(hours: 12));
      final vHrv  = await _avgOf(s, e, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
      final vHr   = await _avgOf(s, e, HealthDataType.HEART_RATE);
      final vResp = await _avgOf(s, e, HealthDataType.RESPIRATORY_RATE);
      final vBt   = await _avgOf(s, e, HealthDataType.BODY_TEMPERATURE);
      if (vHrv  != null) hrv.add(vHrv);
      if (vHr   != null) hr.add(vHr);
      if (vResp != null) resp.add(vResp);
      if (vBt   != null) bt.add(vBt);
    }
    double? med(List<double> xs) {
      if (xs.isEmpty) return null;
      xs.sort();
      final mid = xs.length ~/ 2;
      return xs.length.isOdd ? xs[mid] : (xs[mid-1] + xs[mid]) / 2.0;
    }
    return {
      'HRV':  med(hrv),
      'HR':   med(hr),
      'RESP': med(resp),
      'BT':   med(bt),
    };
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) {
      final n = v.numericValue;
      return n == null ? null : n.toDouble();
    }
    try {
      final any = (v as dynamic).numericValue;
      if (any is num) return any.toDouble();
    } catch (_) {}
    return null;
  }

  // ----------------- 점수화 로직 -----------------
  /// 가중치: HRV 40%, HR 30%, 호흡 15%, 체온 15%
  /// - HRV: 현재/기준선 비율(높을수록 좋음)
  /// - HR:  기준선/현재 비율(낮을수록 좋음)
  /// - 호흡, 체온: 기준선에서의 편차(작을수록 좋음)
  double _computeScore({
    required double? hrvNow,  required double? hrvBase,
    required double? hrNow,   required double? hrBase,
    required double? respNow, required double? respBase,
    required double? btNow,   required double? btBase,
  }) {
    double wHRV = .40, wHR = .30, wResp = .15, wBT = .15;

    double sHRV = _ratioToScore(upIsGood: true, now: hrvNow, base: hrvBase);
    double sHR  = _ratioToScore(upIsGood: false, now: hrNow,  base: hrBase);
    double sResp= _deltaToScore(now: respNow, base: respBase, tol: 1.0);   // ±1 rpm 허용
    double sBT  = _deltaToScore(now: btNow,   base: btBase,   tol: 0.1);   // ±0.1℃ 허용

    // 데이터가 없으면 가중치 자동 재분배
    final parts = <double>[];
    final ws = <double>[];

    if (!sHRV.isNaN) { parts.add(sHRV); ws.add(wHRV); }
    if (!sHR.isNaN)  { parts.add(sHR);  ws.add(wHR);  }
    if (!sResp.isNaN){ parts.add(sResp); ws.add(wResp); }
    if (!sBT.isNaN)  { parts.add(sBT);   ws.add(wBT);  }

    final wSum = ws.fold<double>(0, (a, b) => a + b);
    if (parts.isEmpty || wSum <= 0) return 50;
    double acc = 0;
    for (int i = 0; i < parts.length; i++) {
      acc += parts[i] * (ws[i] / wSum);
    }
    return acc;
  }

  // 비율을 점수(0~100)로: 1.10 이상=100, 1.00=80, 0.90=60, 0.80=40, 그 미만은 20까지 선형 감쇠
  double _ratioToScore({required bool upIsGood, required double? now, required double? base}) {
    if (now == null || base == null || base <= 0) return double.nan;
    final ratio = upIsGood ? (now / base) : (base / now);
    if (ratio >= 1.10) return 100;
    if (ratio >= 1.00) return 80 + (ratio - 1.00) * (20 / 0.10);
    if (ratio >= 0.90) return 60 + (ratio - 0.90) * (20 / 0.10);
    if (ratio >= 0.80) return 40 + (ratio - 0.80) * (20 / 0.10);
    return 20 * (ratio / 0.80).clamp(0.0, 1.0);
  }

  // 편차를 점수(0~100)로: |now-base| <= tol → 90~100, tol~2*tol → 70~90, 그 이후 완만히 하락
  double _deltaToScore({required double? now, required double? base, required double tol}) {
    if (now == null || base == null) return double.nan;
    final d = (now - base).abs();
    if (d <= tol)   return 95 - (d/tol)*5;          // 95~90
    if (d <= 2*tol) return 90 - ((d-tol)/tol)*20;   // 90~70
    if (d <= 4*tol) return 70 - ((d-2*tol)/(2*tol))*30; // 70~40
    return (40 - (d - 4*tol)).clamp(10, 40);        // 바닥 10
  }

  (String, Color) _stageFromScore(double s) {
    if (s >= 80) return ('회복↑', Colors.green);
    if (s >= 60) return ('양호', Colors.teal);
    if (s >= 40) return ('주의', Colors.orange);
    return ('휴식 필요', Colors.red);
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: const Text('스트레스 / 회복 상태'),
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ],
    );

    if (_loading) {
      return Scaffold(appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) _ErrorBanner(text: _error!),

            _ScoreCard(
              score: _score ?? 50,
              stage: _stage ?? '정보 부족',
              color: _color,
              caption: _adviceFor(_stage),
            ),
            const SizedBox(height: 12),

            _MiniMetrics(
              hrvNow: _hrvNow, hrvBase: _hrvBase,
              hrNow: _hrNow, hrBase: _hrBase,
              respNow: _respNow, respBase: _respBase,
              tempNow: _tempNow, tempBase: _tempBase,
            ),

            const SizedBox(height: 8),
            Text(
              '개인 기준선은 최근 3일의 야간 평균으로 계산됩니다. 값은 기기/상황에 따라 달라질 수 있어요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  String _adviceFor(String? stage) {
    switch (stage) {
      case '회복↑':
        return '컨디션 좋음. 가벼운 유산소나 스트레칭으로 흐름을 이어가세요.';
      case '양호':
        return '무리하지 않는 선에서 평소 루틴을 유지하세요.';
      case '주의':
        return '강도 조절이 필요해요. 수분·영양/가벼운 산책/호흡 훈련을 권장합니다.';
      case '휴식 필요':
        return '오늘은 충분한 휴식과 수면을 최우선으로. 무리한 운동은 피하세요.';
      default:
        return '데이터를 더 쌓으면 개인화 정확도가 올라갑니다.';
    }
  }
}

// ----------------- 보조 위젯 -----------------
class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final int score;      // 0~100
  final String stage;   // 회복↑/양호/주의/휴식 필요
  final Color color;
  final String caption;

  const _ScoreCard({
    required this.score,
    required this.stage,
    required this.color,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 상태 배지 + 점수
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  stage,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
              ),
              const Spacer(),
              Text('$score',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  )),
            ],
          ),
          const SizedBox(height: 10),

          // 진행바
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              minHeight: 10,
              color: color,
              backgroundColor: color.withOpacity(.15),
            ),
          ),
          const SizedBox(height: 10),

          // 한줄 조언
          Text(
            caption,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetrics extends StatelessWidget {
  final double? hrvNow, hrvBase;
  final double? hrNow, hrBase;
  final double? respNow, respBase;
  final double? tempNow, tempBase;

  const _MiniMetrics({
    required this.hrvNow, required this.hrvBase,
    required this.hrNow,  required this.hrBase,
    required this.respNow, required this.respBase,
    required this.tempNow, required this.tempBase,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _miniRow(
          context: context,
          label: 'HRV',
          now: hrvNow, base: hrvBase,
          unit: 'ms',
          better: '높을수록 좋음',
        ),
        const SizedBox(height: 6),
        _miniRow(
          context: context,
          label: '심박',
          now: hrNow, base: hrBase,
          unit: 'bpm',
          better: '낮을수록 안정',
        ),
        const SizedBox(height: 6),
        _miniRow(
          context: context,
          label: '호흡수',
          now: respNow, base: respBase,
          unit: 'rpm',
          better: '기준선과 유사할수록 좋음',
        ),
        const SizedBox(height: 6),
        _miniRow(
          context: context,
          label: '체온',
          now: tempNow, base: tempBase,
          unit: '°C',
          better: '기준선과 유사할수록 좋음',
        ),
      ],
    );
  }

  Widget _miniRow({
    required BuildContext context,
    required String label,
    required double? now,
    required double? base,
    required String unit,
    required String better,
  }) {
    final has = now != null && base != null;
    final color = has ? Colors.black87 : Colors.grey[600];

    String right;
    if (!has) {
      right = '데이터 없음';
    } else {
      final df = NumberFormat('0.0');
      final delta = now! - base!;
      final sign = delta > 0 ? '+' : '';
      right = '${df.format(now)} $unit  ($sign${df.format(delta)})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(better,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
          ),
          Text(right, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
