// lib/pages/health_summary_page.dart
import 'package:finalhealthcheck/pages/fecal_occult_blood_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';

import 'steps_page.dart';
import 'sleep_detail_page.dart';
import 'base_health_page.dart';

/// 날짜 범위
enum SummaryRange { today, week, month }

class HealthSummaryPage extends HealthStatefulPage {
  const HealthSummaryPage({super.key});
  @override
  State<HealthSummaryPage> createState() => _HealthSummaryPageState();
}

class _HealthSummaryPageState extends HealthState<HealthSummaryPage> {
  @override
  List<HealthDataType> get types => const [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP, // 가능하면 ASLEEP 우선
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  ];

  SummaryRange _range = SummaryRange.today;
  bool _loading = true;

  _SummaryDummy? _data; // 스켈레톤 플래시 방지

  @override
  void initState() {
    super.initState();
    authReady.then((_) {
      if (!mounted) return;
      _load();
    });
  }

  // ---------------- Helpers ----------------
  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) {
      final n = v.numericValue;
      return n == null ? null : n.toDouble();
    }
    return null;
  }

  Future<int?> _sumSteps(DateTime start, DateTime end) async {
    try {
      final agg = await health.getTotalStepsInInterval(start, end);
      if (agg != null) return agg;
    } catch (_) {}
    try {
      final pts = await health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );
      double sum = 0;
      for (final p in pts) {
        final d = _asDouble(p.value);
        if (d != null) sum += d;
      }
      return sum.round();
    } catch (_) {
      return null;
    }
  }

  /// [winStart, winEnd) 수면 총합. ASLEEP 있으면 우선 사용, 없으면 SESSION.
  Future<Duration?> _sleepTotalInWindow(DateTime winStart, DateTime winEnd) async {
    try {
      final pts = await health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION],
        startTime: winStart,
        endTime: winEnd,
      );
      final asleep = pts.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
      final base = asleep.isNotEmpty
          ? asleep
          : pts.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();

      int minSum = 0;
      for (final p in base) {
        final a = p.dateFrom, b = p.dateTo;
        if (a == null || b == null) continue;
        final s = a.isAfter(winStart) ? a : winStart;
        final e = b.isBefore(winEnd) ? b : winEnd;
        final d = e.difference(s).inMinutes;
        if (d > 0) minSum += d;
      }
      if (minSum <= 0) return null;
      return Duration(minutes: minSum);
    } catch (_) {
      return null;
    }
  }

  /// 최근 N일 걸음 평균(결측 제외). today0 기준, **오늘 제외**하고 i=1..N.
  Future<int?> _stepsBaselineNDays(int n, DateTime today0) async {
    int sum = 0, cnt = 0;
    for (int i = 1; i <= n; i++) {
      final d0 = today0.subtract(Duration(days: i));
      final d1 = d0.add(const Duration(days: 1));
      final s = await _sumSteps(d0, d1);
      if (s != null) {
        sum += s;
        cnt++;
      }
    }
    if (cnt == 0) return null;
    return (sum / cnt).round();
  }

  /// 최근 N밤 수면 평균(결측 제외). today0 기준, **지난밤 제외**하고 i=2..(N+1).
  /// 밤 윈도우: anchor(=당일 00시) 기준 18:00 ~ 다음날 12:00
  Future<Duration?> _sleepBaselineNNights(int n, DateTime today0) async {
    int sumMin = 0, cnt = 0;
    for (int i = 2; i <= n + 1; i++) {
      final anchor = today0.subtract(Duration(days: i - 1)); // i=2 -> 어제 이전
      final winStart = anchor.subtract(const Duration(hours: 6)); // 18:00
      final winEnd = anchor.add(const Duration(hours: 12)); // 다음날 12:00
      final dur = await _sleepTotalInWindow(winStart, winEnd);
      if (dur != null && dur.inMinutes > 0) {
        sumMin += dur.inMinutes;
        cnt++;
      }
    }
    if (cnt == 0) return null;
    return Duration(minutes: (sumMin / cnt).round());
  }

  /// 오늘/어젯밤 ↔ 기준선 화살표 판단
  /// metric: 'steps' | 'sleep'
  int _trendArrowByMetric({
    required double today,
    required double baseline,
    required String metric,
  }) {
    if (baseline <= 0) return 0;
    final ratio = (today - baseline) / baseline;

    switch (metric) {
      case 'steps': // ±15%
        if (ratio >= 0.15) return 1;
        if (ratio <= -0.15) return -1;
        return 0;
      case 'sleep': // ±10%
        if (ratio >= 0.10) return 1;
        if (ratio <= -0.10) return -1;
        return 0;
      default:
        return 0;
    }
  }

  /// fecal(잠혈) 검사 주기 스케줄러
  /// - last: 마지막 검사일(없으면 오늘-주기 로 가정하여 '지금부터 시작')
  /// - cycleDays: 권장 주기(기본 90일)
  /// - soonThresholdDays: 임박 경계(기본 7일)
  ({
  DateTime nextDueAt,
  int daysToDue,
  int grade, // 2 good(여유), 1 warn(임박), 0 bad(연체)
  }) _calcFecalDue({
    required DateTime? last,
    int cycleDays = 90,
    int soonThresholdDays = 7,
  }) {
    final today = DateTime.now();
    final base = last ?? today; // 마지막 검사 없으면 오늘을 기준으로 시작
    final next = DateTime(base.year, base.month, base.day).add(Duration(days: cycleDays));

    final diff = next.difference(DateTime(today.year, today.month, today.day)).inDays;
    // 등급: 연체(<0)=0, 임박(<=7)=1, 여유(>7)=2
    final g = diff < 0 ? 0 : (diff <= soonThresholdDays ? 1 : 2);

    return (nextDueAt: next, daysToDue: diff, grade: g);
  }


  // ---------------- Load ----------------
  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);
      final tomorrow0 = today0.add(const Duration(days: 1));

      int? todaySteps;
      int? stepsAvg; // 7일/30일 평균(결측 제외)
      int? stepsTrend; // 오늘만
      int? stepsGrade;

      Duration? sleepLastNight;
      Duration? sleepAvg; // 7밤/30밤 평균(결측 제외)
      int? sleepTrend; // 오늘만
      int? sleepGrade;

      if (authorized) {
        // ---- 걸음 (오늘)
        todaySteps = await _sumSteps(today0, tomorrow0);
        if (todaySteps != null) {
          stepsGrade = (todaySteps >= 8000 ? 2 : (todaySteps >= 4000 ? 1 : 0));
        }

        // ---- 수면 (어젯밤: 18:00 ~ 오늘 12:00)
        final winStart = today0.subtract(const Duration(hours: 6));
        final winEnd = today0.add(const Duration(hours: 12));
        sleepLastNight = await _sleepTotalInWindow(winStart, winEnd);
        if (sleepLastNight != null) {
          final m = sleepLastNight.inMinutes;
          sleepGrade = (m >= 420 ? 2 : (m >= 300 ? 1 : 0)); // 7h / 5h
        }

        // ---- 기준선 (오늘 탭 화살표용)
        if (_range == SummaryRange.today) {
          // steps baseline: 직전 7일(오늘 제외)
          final sb = await _stepsBaselineNDays(7, today0);
          if (sb != null && todaySteps != null) {
            stepsTrend = _trendArrowByMetric(
              today: todaySteps.toDouble(),
              baseline: sb.toDouble(),
              metric: 'steps',
            );
          }

          // sleep baseline: 직전 7밤(지난밤 제외)
          final slb = await _sleepBaselineNNights(7, today0);
          if (slb != null && sleepLastNight != null) {
            stepsTrend ??= 0; // null safety
            sleepTrend = _trendArrowByMetric(
              today: sleepLastNight.inMinutes.toDouble(),
              baseline: slb.inMinutes.toDouble(),
              metric: 'sleep',
            );
          }
        } else {
          // ---- 범위 탭: 평균만(결측 제외)
          final days = _range == SummaryRange.week ? 7 : 30;

          // 걸음: i=0..(days-1) 중 기록 있는 날만 평균 (오늘 포함)
          int stepSum = 0, stepCnt = 0;
          for (int i = 0; i < days; i++) {
            final d0 = today0.subtract(Duration(days: i));
            final d1 = d0.add(const Duration(days: 1));
            final s = await _sumSteps(d0, d1);
            if (s != null) {
              stepSum += s;
              stepCnt++;
            }
          }
          if (stepCnt > 0) stepsAvg = (stepSum / stepCnt).round();

          // 수면: 최근 N밤 평균(지난밤 포함, 결측 제외)
          int sumMin = 0, cnt = 0;
          for (int i = 0; i < days; i++) {
            final anchor = today0.subtract(Duration(days: i));
            final s = await _sleepTotalInWindow(
              anchor.subtract(const Duration(hours: 6)),
              anchor.add(const Duration(hours: 12)),
            );
            if (s != null && s.inMinutes > 0) {
              sumMin += s.inMinutes;
              cnt++;
            }
          }
          if (cnt > 0) sleepAvg = Duration(minutes: (sumMin / cnt).round());
        }
      }

      // ✅ 대변검사 스케줄 계산 (더미 lastTestAt: 20일 전)
      final DateTime? fecalLastTestAt = DateTime.now().subtract(const Duration(days: 20));
      // 권장 주기 30일, 임박 7일 기준
      final fecalSched = _calcFecalDue(last: fecalLastTestAt, cycleDays: 30, soonThresholdDays: 7);

      // 더미(바이탈/계측) + 실데이터 반영
      _data = _SummaryDummy(
        // 활동
        stepsToday: todaySteps,
        stepsAvg: stepsAvg,
        stepsTrend: stepsTrend,
        stepsGrade: stepsGrade,
        // 수면
        sleepYesterday: sleepLastNight,
        sleepAvg: sleepAvg,
        sleepTrend: sleepTrend,
        sleepGrade: sleepGrade,
        // 나머지 더미
        hrAvg: 68,
        hrvRmssd: 45,
        hrGrade: 2,
        hrvTrend: 0,
        bpSys: 122,
        bpDia: 78,
        bpGrade: 2,
        bpTrend: 0,
        glucoseFasting: 92,
        glucosePost: 128,
        glucoseGrade: 2,
        glucoseTrend: 0,
        weight: 64.4,
        weightDeltaKg: 0.2,
        weightGrade: 2,
        weightTrend: 0,
        urinalysisGrade: 2,
        urinalysisSummary: '정상',
        fecalLastTestAt: fecalLastTestAt,
        fecalCycleDays: 90,
        fecalLastResult: '잠혈 없음',           // 나중에 사용자 입력으로 갱신
        fecalDueGrade: fecalSched.grade,       // 색상 등급
        fecalNextDueAt: fecalSched.nextDueAt,  // 다음 검사 예정일
        fecalDaysToDue: fecalSched.daysToDue,  // D-값
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    String rangeLabel(SummaryRange r) => switch (r) {
      SummaryRange.today => '오늘',
      SummaryRange.week => '7일',
      SummaryRange.month => '30일',
    };
    final df = DateFormat('M/d');

    final appBar = AppBar(
      title: const Text('건강 요약'),
      actions: [
        PopupMenuButton<SummaryRange>(
          initialValue: _range,
          onSelected: (r) {
            setState(() => _range = r);
            _load();
          },
          itemBuilder: (_) => [
            for (final r in SummaryRange.values)
              PopupMenuItem(value: r, child: Text(rangeLabel(r))),
          ],
          icon: const Icon(Icons.date_range),
          tooltip: '날짜 범위',
        ),
      ],
    );

    if (_loading || _data == null) {
      return Scaffold(
        appBar: appBar,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _SkeletonTile(),
            SizedBox(height: 8),
            _SkeletonTile(),
            SizedBox(height: 8),
            _SkeletonTile(),
            SizedBox(height: 16),
            Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    final d = _data!;
    final showTrend = _range == SummaryRange.today;

    return Scaffold(
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  errorMsg!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            // 활동
            const _SectionTitle('활동 요약'),
            _SummaryTile(
              title: '활동량',
              subtitle: _range == SummaryRange.today
                  ? (d.stepsToday == null
                  ? '기록 없음'
                  : '${_fmtSteps(d.stepsToday!)} 걸음')
                  : (d.stepsAvg == null
                  ? '기록 없음'
                  : '평균 ${_fmtSteps(d.stepsAvg!)} 걸음'),
              status: _gradeToStatus(d.stepsGrade ?? 1),
              trend: d.stepsTrend ?? 0,
              icon: Icons.directions_walk,
              showTrend: showTrend,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StepsPage()),
              ),
            ),
            const SizedBox(height: 8),

            // 수면
            const _SectionTitle('수면'),
            _SummaryTile(
              title: '수면 요약',
              subtitle: _range == SummaryRange.today
                  ? (d.sleepYesterday == null
                  ? '기록 없음'
                  : _fmtDur(d.sleepYesterday!))
                  : (d.sleepAvg == null
                  ? '기록 없음'
                  : '평균 ${_fmtDur(d.sleepAvg!)}'),
              status: _gradeToStatus(d.sleepGrade ?? 1),
              trend: d.sleepTrend ?? 0,
              icon: Icons.bedtime_outlined,
              showTrend: showTrend,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SleepDetailPage()),
              ),
            ),
            const SizedBox(height: 8),

            // 바이탈 (더미)
            const _SectionTitle('바이탈'),
            _SummaryTile(
              title: '심박수(+HRV)',
              subtitle: 'HR ${d.hrAvg} bpm\nHRV ${d.hrvRmssd} ms',
              status: _gradeToStatus(d.hrGrade),
              trend: d.hrvTrend,
              icon: Icons.monitor_heart_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _WipPage(title: '심박/HRV')),
              ),
            ),
            const SizedBox(height: 8),

            // 계측 (더미)
            const _SectionTitle('진단/계측'),
            _SummaryTile(
              title: '혈압',
              subtitle: '${d.bpSys}/${d.bpDia} mmHg',
              status: _gradeToStatus(d.bpGrade),
              trend: d.bpTrend,
              icon: Icons.favorite_outline,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _WipPage(title: '혈압')),
              ),
            ),
            const SizedBox(height: 8),
            _SummaryTile(
              title: '혈당',
              subtitle: '식전 ${d.glucoseFasting} mg/dL\n식후 ${d.glucosePost} mg/dL',
              status: _gradeToStatus(d.glucoseGrade),
              trend: d.glucoseTrend,
              icon: Icons.bloodtype_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _WipPage(title: '혈당')),
              ),
            ),
            const SizedBox(height: 8),
            _SummaryTile(
              title: '체중',
              subtitle: d.weight.toStringAsFixed(1) + ' kg',
              status: _gradeToStatus(d.weightGrade),
              trend: d.weightTrend,
              icon: Icons.monitor_weight_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _WipPage(title: '체중')),
              ),
            ),
            const SizedBox(height: 8),

            // 소변 검사
            _SectionTitle('소변/대변 검사'),
            _SummaryTile(
              title: '소변검사',
              subtitle: d.urinalysisSummary,             // 문자열 요약
              status: _gradeToStatus(d.urinalysisGrade), // 색상 반영
              trend: 0,
              icon: Icons.science_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _WipPage(title: '소변검사')),
              ),
            ),
            const SizedBox(height: 8),

            // 대변검사(잠혈) - 주기/예정 안내형
            _SummaryTile(
              title: '대변검사(잠혈)',
              // 예: "다음 검사: 3/12 (D-5)\n마지막 결과: 잠혈 없음"
              subtitle: () {
                final next = d.fecalNextDueAt;
                final df = DateFormat('M/d');
                final dDay = d.fecalDaysToDue; // 음수면 D+ (연체)
                final lastResult = d.fecalLastResult;
                return '다음 검사까지:\n$dDay일';
              }(),
              status: _gradeToStatus(d.fecalDueGrade), // 여유/임박/연체 → 초록/노랑/빨강
              trend: 0,
              icon: Icons.event_repeat_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FecalOccultBloodPage(),
                ),
              ),
            ),
            const SizedBox(height: 8),

            const SizedBox(height: 16),
            Text(
              '${df.format(DateTime.now())} 기준 • 의료적 판단은 의료진과 상의하세요.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 표현 유틸 ----------
  static String _fmtSteps(int v) => NumberFormat('#,###').format(v);

  static String _fmtDur(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return '${h}시간 ${m}분';
  }

  static String _deltaStr(double v) {
    if (v == 0) return '변화 없음';
    return (v > 0 ? '+' : '') + v.toStringAsFixed(1) + ' kg';
  }

  static _Status _gradeToStatus(int g) => switch (g) {
    2 => _Status.good,
    1 => _Status.warn,
    _ => _Status.bad,
  };
}

/// 상태 등급
enum _Status { good, warn, bad }

/// 요약 타일 (오른쪽 영역 폭 고정 + 숫자만 크게)
class _SummaryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final _Status status;
  final int trend; // -1/0/+1
  final IconData icon;
  final VoidCallback? onTap;
  final bool showTrend;

  // 오른쪽(수치+화살표) 영역 고정 폭
  static const double _trailingWidth = 160.0;
  static const double _arrowBoxWidth = 24.0;

  const _SummaryTile({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.trend,
    required this.icon,
    required this.onTap,
    this.showTrend = true,
  });

  // 숫자만 크게 만들기 위한 정규식
  static final RegExp _numRe = RegExp(r'(\d[\d,]*(?:\.\d+)?)');

  InlineSpan _buildSubtitleSpan(BuildContext context, String text) {
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.grey[800],
      fontSize: 15,
    ) ??
        const TextStyle(fontSize: 18, color: Colors.black87);

    final numStyle = base.copyWith(
      fontSize: (base.fontSize ?? 17) + 6, // 숫자만 +6pt
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -0.2,
    );

    final spans = <TextSpan>[];
    int cursor = 0;

    for (final m in _numRe.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
      }
      final numTxt = m.group(0) ?? '';
      spans.add(TextSpan(text: numTxt, style: numStyle));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final c = switch (status) {
      _Status.good => Colors.green,
      _Status.warn => Colors.orange,
      _Status.bad => Colors.red,
    };
    final bg = c.withOpacity(.10);

    final arrowIcon =
    trend > 0 ? Icons.arrow_upward : (trend < 0 ? Icons.arrow_downward : Icons.horizontal_rule);
    final arrowColor =
    trend > 0 ? Colors.green : (trend < 0 ? Colors.red : Colors.grey[600]);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withOpacity(.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: c.withOpacity(.18),
              child: Icon(icon, color: c),
            ),
            const SizedBox(width: 12),

            // 제목(한글 큼/굵게)
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.2,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // 오른쪽 고정 폭 영역(수치 + 화살표)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _trailingWidth,
                maxWidth: _trailingWidth,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 수치(숫자만 크게) — 우측 정렬
                  Expanded(
                    child: Text.rich(
                      _buildSubtitleSpan(context, subtitle),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 화살표: 표시 안 해도 공간은 유지(레이아웃 안정)
                  SizedBox(
                    width: _arrowBoxWidth,
                    child: Opacity(
                      opacity: showTrend ? 1.0 : 0.0,
                      child: Icon(arrowIcon, size: 18, color: arrowColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 로딩 플레이스홀더(간단)
class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

/// -------- 데이터 컨테이너 --------
/// 걸음/수면은 실데이터만 사용(없으면 '기록 없음' 표기). 나머지는 더미.
class _SummaryDummy {
  // 활동
  final int? stepsToday;
  final int? stepsAvg;
  final int? stepsTrend; // 오늘만
  final int? stepsGrade; // 0/1/2

  // 수면
  final Duration? sleepYesterday;
  final Duration? sleepAvg;
  final int? sleepTrend; // 오늘만
  final int? sleepGrade;

  // HR/HRV (더미)
  final int hrAvg;
  final int hrvRmssd;
  final int hrGrade;
  final int hrvTrend;

  // 혈압/혈당/체중 (더미)
  final int bpSys;
  final int bpDia;
  final int bpGrade;
  final int bpTrend;

  final int glucoseFasting;
  final int glucosePost;
  final int glucoseGrade;
  final int glucoseTrend;

  final double weight;
  final double weightDeltaKg;
  final int weightGrade;
  final int weightTrend;

  // 소변/대변 검사 요약
  final int urinalysisGrade;         // 0/1/2 (빨/노/초)
  final String urinalysisSummary;    // 예: '정상 (모든 항목 음성)'
  final DateTime? fecalLastTestAt;     // 마지막 검사일 (사용자 기록)
  final int fecalCycleDays;            // 권장 검사 주기 (예: 90일)
  final String fecalLastResult;        // 최근 결과 요약 (예: '잠혈 없음' / '잠혈 의심')
  final int fecalDueGrade;             // 2:정상(여유), 1:임박, 0:연체  → 색상에 사용
  final DateTime fecalNextDueAt;       // 다음 권장 검사일
  final int fecalDaysToDue;            // D-값 (음수면 연체)

  const _SummaryDummy({
    required this.stepsToday,
    required this.stepsAvg,
    required this.stepsTrend,
    required this.stepsGrade,
    required this.sleepYesterday,
    required this.sleepAvg,
    required this.sleepTrend,
    required this.sleepGrade,
    required this.hrAvg,
    required this.hrvRmssd,
    required this.hrGrade,
    required this.hrvTrend,
    required this.bpSys,
    required this.bpDia,
    required this.bpGrade,
    required this.bpTrend,
    required this.glucoseFasting,
    required this.glucosePost,
    required this.glucoseGrade,
    required this.glucoseTrend,
    required this.weight,
    required this.weightDeltaKg,
    required this.weightGrade,
    required this.weightTrend,
    required this.urinalysisGrade,
    required this.urinalysisSummary,
    required this.fecalLastTestAt,
    required this.fecalCycleDays,
    required this.fecalLastResult,
    required this.fecalDueGrade,
    required this.fecalNextDueAt,
    required this.fecalDaysToDue,
  });
}

/// 섹션 제목(한글 더 굵고 크게)
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// 임시 WIP 페이지(상세 미구현용)
class _WipPage extends StatelessWidget {
  final String title;
  const _WipPage({required this.title, super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('개발중', style: TextStyle(fontSize: 18))),
    );
  }
}
