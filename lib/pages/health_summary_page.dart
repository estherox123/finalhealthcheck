// lib/pages/health_summary_page.dart
/// 헬스 데이터 요약 페이지 (워치 연동 반영: HR/HRV/호흡/체온 실데이터)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'base_health_page.dart';
import 'sleep_detail_page.dart';
import 'steps_page.dart';
import '../data/recovery_score.dart' as rec;
import '../reports/health_exporter.dart';
import '../reports/health_report_models.dart';
import '../reports/health_report_pdf.dart';
import 'fecal_occult_blood_page.dart';
import 'stress_recovery_page.dart';

/// 날짜 범위
enum SummaryRange { today, week, month }

class HealthSummaryPage extends HealthStatefulPage {
  const HealthSummaryPage({super.key});
  @override
  State<HealthSummaryPage> createState() => _HealthSummaryPageState();
}

class _HealthSummaryPageState extends HealthState<HealthSummaryPage> {
  // 이 페이지에서 권한 요청/유지할 타입들 (플러그인이 지원하는 항목만!)
  @override
  List<HealthDataType> get types => const [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.BODY_TEMPERATURE,
    // TODO(v0.2): 가능하면 SpO₂ / SLEEP_AWAKE 타입도 추가
    // HealthDataType.BLOOD_OXYGEN,        // 실제 enum 이름 확인 필요
    // HealthDataType.SLEEP_AWAKE,

  ];

  SummaryRange _range = SummaryRange.today;
  bool _loading = true;

  _SummaryModel? _data; // 스켈레톤 번쩍임 방지용 캐시

  @override
  void initState() {
    super.initState();
    authReady.then((_) {
      if (!mounted) return;
      _load();
    });
  }

  // ---------------- 공통 헬퍼 ----------------

  double? _numVal(dynamic v) {
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
        final d = _numVal(p.value);
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

  /// 범용 평균 수집: 주어진 타입의 값 평균 (결측 시 null)
  Future<double?> _avgOfType(DateTime start, DateTime end, HealthDataType t) async {
    try {
      final pts = await health.getHealthDataFromTypes(
        types: [t],
        startTime: start,
        endTime: end,
      );
      final vals = <double>[];
      for (final p in pts) {
        final v = _numVal(p.value);
        if (v != null && v.isFinite) vals.add(v);
      }
      if (vals.isEmpty) return null;
      final sum = vals.reduce((a, b) => a + b);
      return sum / vals.length;
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

  /// 최근 3박 + 오늘 밤 기준으로 회복 점수 계산.
  /// today0: 오늘 00:00
  Future<rec.RecoveryScore?> _loadTodayRecoveryScore(DateTime today0) async {
    if (!authorized) return null;

    // 오늘 포함 4밤 (3일 history + 오늘)
    final nights = <rec.NightRecoveryRaw>[];

    // 오래된 밤부터 쌓기 (오름차순)
    for (int i = 3; i >= 0; i--) {
      final anchor = today0.subtract(Duration(days: i));
      final winStart = anchor.subtract(const Duration(hours: 6));  // 18:00
      final winEnd = anchor.add(const Duration(hours: 12));        // 다음날 12:00

      final sleep = await _sleepTotalInWindow(winStart, winEnd);
      final hrMean = await _avgOfType(
        winStart,
        winEnd,
        HealthDataType.HEART_RATE,
      );
      final hrv = await _avgOfType(
        winStart,
        winEnd,
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      );
      final resp = await _avgOfType(
        winStart,
        winEnd,
        HealthDataType.RESPIRATORY_RATE,
      );

      // TODO: 나중에 SpO₂/각성 횟수/기상 시각까지 채우고 싶으면 여기서 같이 계산
      const int? awakenings = null;
      const double? spo2Min = null;

      // 완전히 비어 있는 밤은 스킵
      if (sleep == null &&
          hrMean == null &&
          hrv == null &&
          resp == null &&
          spo2Min == null) {
        continue;
      }

      nights.add(
        rec.NightRecoveryRaw(
          nightDate: anchor,
          hrMean: hrMean,
          hrvRmssd: hrv,
          respRate: resp,
          sleepTotal: sleep,
          sleepAwakenings: awakenings,
          spo2Min: spo2Min,
        ),
      );
    }

    if (nights.isEmpty) return null;

    // nights는 과거→현재 오름차순이므로 그대로 사용
    return rec.computeRecoveryFromNights(nights);
  }

  String _recoveryLabelText(rec.RecoveryLabel? label) {
    switch (label) {
      case rec.RecoveryLabel.recoveryUp:
        return '회복↑';
      case rec.RecoveryLabel.good:
        return '양호';
      case rec.RecoveryLabel.caution:
        return '주의';
      case rec.RecoveryLabel.needRest:
        return '휴식 필요';
      default:
        return '추정 중';
    }
  }

  _Status _recoveryLabelToStatus(rec.RecoveryLabel? label) {
    switch (label) {
      case rec.RecoveryLabel.recoveryUp:
      case rec.RecoveryLabel.good:
        return _Status.good;
      case rec.RecoveryLabel.caution:
        return _Status.warn;
      case rec.RecoveryLabel.needRest:
        return _Status.bad;
      default:
      // 데이터가 없거나 baseline 부족일 때: 일단 warn
        return _Status.warn;
    }
  }

  /// fecal(잠혈) 검사 주기 스케줄러
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

  Future<({DateTime start, DateTime end, String label})> _currentRange() async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final start = switch (_range) {
      SummaryRange.today => end.subtract(const Duration(days: 1)),
      SummaryRange.week => end.subtract(const Duration(days: 7)),
      SummaryRange.month => end.subtract(const Duration(days: 30)),
    };
    final label = switch (_range) {
      SummaryRange.today => '오늘',
      SummaryRange.week => '최근 7일',
      SummaryRange.month => '최근 30일',
    };
    return (start: start, end: end, label: label);
  }

  Future<void> _openPdfPreview() async {
    final r = await _currentRange();
    // 1) 범위의 모든 타입 수집
    final exporter = HealthExporter(health);
    final rows = await exporter.collect(
      start: r.start,
      end: r.end,
      types: const [
        HealthDataType.STEPS,
        HealthDataType.SLEEP_SESSION,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_GLUCOSE,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.BODY_MASS_INDEX,
      ],
    );

    final pdfBytes = await HealthReportPdf.build(
      HealthReportData(
        generatedAt: DateTime.now(),
        subjectName: '홍길동', // 사용자 이름 있으면 바꿔 주기
        rangeLabel: r.label,
        records: rows,
      ),
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfPreview(
          build: (fmt) async => Uint8List.fromList(pdfBytes),
          pdfFileName: "health_report.pdf",
          allowPrinting: true,
          allowSharing: true,
          canChangeOrientation: false,
          canChangePageFormat: false,
        ),
      ),
    );
  }

  Future<void> _exportCsvAndShare() async {
    final r = await _currentRange();
    final exporter = HealthExporter(health);
    final rows = await exporter.collect(
      start: r.start,
      end: r.end,
      types: const [
        HealthDataType.STEPS,
        HealthDataType.SLEEP_SESSION,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_GLUCOSE,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.BODY_MASS_INDEX,
      ],
    );

    final csv = HealthRecord.toCsv(rows);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/health_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csv, encoding: utf8);

    await Share.shareXFiles([XFile(file.path)], text: '${r.label} 헬스 데이터 내보내기 (CSV)');
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

      // 바이탈 (실데이터; 없으면 null 유지)
      double? hrAvg; // bpm (오늘)
      double? hrvAvg; // ms (야간)
      double? respAvg; // rpm (야간)
      double? btAvg; // °C (야간)

      // 회복 지표
      rec.RecoveryScore? recovery;

      if (authorized) {
        // ---- 걸음 (오늘)
        todaySteps = await _sumSteps(today0, tomorrow0);
        if (todaySteps != null) {
          stepsGrade =
          (todaySteps >= 8000 ? 2 : (todaySteps >= 4000 ? 1 : 0));
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
          if (cnt > 0) {
            sleepAvg = Duration(minutes: (sumMin / cnt).round());
          }
        }

        // ---- 바이탈: HR/HRV/호흡/체온 ----
        final winStartForVitals = today0.subtract(const Duration(hours: 6));
        final winEndForVitals = today0.add(const Duration(hours: 12));

        hrAvg = await _avgOfType(
            today0, tomorrow0, HealthDataType.HEART_RATE);
        hrvAvg = await _avgOfType(winStartForVitals, winEndForVitals,
            HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
        respAvg = await _avgOfType(
            winStartForVitals, winEndForVitals, HealthDataType.RESPIRATORY_RATE);
        btAvg = await _avgOfType(
            winStartForVitals, winEndForVitals, HealthDataType.BODY_TEMPERATURE);

        // ---- 회복 지표 (오늘 탭일 때만) ----
        if (_range == SummaryRange.today) {
          recovery = await _loadTodayRecoveryScore(today0);
        }
      }

      // ---- 대변검사 스케줄 계산 (권한 여부와 무관) ----
      final DateTime? fecalLastTestAt =
      DateTime.now().subtract(const Duration(days: 20));
      final fecalSched =
      _calcFecalDue(last: fecalLastTestAt, cycleDays: 30, soonThresholdDays: 7);

      _data = _SummaryModel(
        // 회복 지표
        recoveryScore: recovery?.score,
        recoveryLabel: recovery?.label,
        recoveryLowConfidence: recovery?.lowConfidence,
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
        // ---- 바이탈(실데이터) ----
        hrAvg: hrAvg,
        hrvRmssd: hrvAvg,
        respRate: respAvg,
        bodyTempC: btAvg,
        // ---- 이하 더미 유지 ----
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
        fecalLastResult: '잠혈 없음',
        fecalDueGrade: fecalSched.grade,
        fecalNextDueAt: fecalSched.nextDueAt,
        fecalDaysToDue: fecalSched.daysToDue,
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
        IconButton(
          tooltip: 'PDF 보고서',
          icon: const Icon(Icons.picture_as_pdf),
          onPressed: _openPdfPreview,
        ),
        IconButton(
          tooltip: 'CSV 내보내기',
          icon: const Icon(Icons.table_view),
          onPressed: _exportCsvAndShare,
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

            // -------- 회복 지표 (오늘만) --------
            if (_range == SummaryRange.today) ...[
              const _SectionTitle('회복 지표'),
              _SummaryTile(
                title: '회복 점수',
                subtitle: () {
                  if (d.recoveryScore == null) return '데이터 부족';
                  final labelText = _recoveryLabelText(d.recoveryLabel);
                  final lc = d.recoveryLowConfidence == true ? '' : '';
                  return '${d.recoveryScore} 점 • $labelText$lc';
                }(),
                status: _recoveryLabelToStatus(d.recoveryLabel),
                trend: 0,
                icon: Icons.bolt_outlined,
                showTrend: false,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                      const StressRecoveryPage(), // 일단 기존 페이지로 라우팅
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // -------- 활동 --------
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

            // -------- 수면 --------
            const _SectionTitle('수면'),
            _SummaryTile(
              title: '수면 요약',
              subtitle: _range == SummaryRange.today
                  ? (d.sleepYesterday == null ? '기록 없음' : _fmtDur(d.sleepYesterday!))
                  : (d.sleepAvg == null ? '기록 없음' : '평균 ${_fmtDur(d.sleepAvg!)}'),
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

            // -------- 바이탈 (실데이터) --------
            const _SectionTitle('바이탈'),

            // HR
            _SummaryTile(
              title: '심박수',
              subtitle: (d.hrAvg == null) ? '기록 없음' : '${d.hrAvg!.toStringAsFixed(0)} bpm',
              status: _gradeToStatus(_gradeByRange(d.hrAvg, low: 50, high: 90)),
              trend: 0,
              icon: Icons.monitor_heart_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _WipPage(title: '심박')),
              ),
            ),
            const SizedBox(height: 8),

            // -------- 진단/계측 (더미 유지) --------
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

            // -------- 소변/대변 --------
            const _SectionTitle('소변/대변 검사'),
            _SummaryTile(
              title: '소변검사',
              subtitle: d.urinalysisSummary,
              status: _gradeToStatus(d.urinalysisGrade),
              trend: 0,
              icon: Icons.science_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _WipPage(title: '소변검사')),
              ),
            ),
            const SizedBox(height: 8),

            _SummaryTile(
              title: '대변검사(잠혈)',
              subtitle: () {
                final dDay = d.fecalDaysToDue; // 음수면 연체(D+)
                return '다음 검사까지:\n$dDay일';
              }(),
              status: _gradeToStatus(d.fecalDueGrade), // 여유/임박/연체 → 초록/노랑/빨강
              trend: 0,
              icon: Icons.event_repeat_outlined,
              showTrend: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FecalOccultBloodPage()),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              '${df.format(DateTime.now())} 기준 • 의료적 판단은 의료진과 상의하세요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
    final arrowColor = trend > 0 ? Colors.green : (trend < 0 ? Colors.red : Colors.grey[600]);

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
/// 걸음/수면/바이탈은 실데이터(null 허용). 그 외는 더미 유지.
class _SummaryModel {
  // ---- 회복 지표 ----
  final int? recoveryScore;                // 0–100
  final rec.RecoveryLabel? recoveryLabel;  // 회복↑/양호/주의/휴식필요
  final bool? recoveryLowConfidence;       // baseline/history 부족 플래그

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

  // ---- 바이탈(실데이터) ----
  final double? hrAvg; // bpm
  final double? hrvRmssd; // ms
  final double? respRate; // rpm
  final double? bodyTempC; // °C

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
  final int urinalysisGrade; // 0/1/2 (빨/노/초)
  final String urinalysisSummary; // 예: '정상 (모든 항목 음성)'
  final DateTime? fecalLastTestAt; // 마지막 검사일 (사용자 기록)
  final int fecalCycleDays; // 권장 검사 주기 (예: 90일)
  final String fecalLastResult; // 최근 결과 요약
  final int fecalDueGrade; // 2:정상(여유), 1:임박, 0:연체
  final DateTime fecalNextDueAt; // 다음 권장 검사일
  final int fecalDaysToDue; // D-값 (음수면 연체)

  const _SummaryModel({
    // 회복 지표
    required this.recoveryScore,
    required this.recoveryLabel,
    required this.recoveryLowConfidence,
    // 활동
    required this.stepsToday,
    required this.stepsAvg,
    required this.stepsTrend,
    required this.stepsGrade,
    // 수면
    required this.sleepYesterday,
    required this.sleepAvg,
    required this.sleepTrend,
    required this.sleepGrade,
    // 바이탈
    required this.hrAvg,
    required this.hrvRmssd,
    required this.respRate,
    required this.bodyTempC,
    // 더미
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

// ---------------- 등급 계산 보조 ----------------
// 값이 null이면 warn(1)로 표기(데이터 없음 = 주의) — 원하면 정책 조정
int _gradeByRange(double? v, {required double low, required double high}) {
  if (v == null) return 1;
  if (v >= low && v <= high) return 2;
  if ((v >= low - 5 && v < low) || (v > high && v <= high + 10)) return 1;
  return 0;
}

int _gradeByThresholdUpBetter(double? v, {required double good, required double warn}) {
  if (v == null) return 1;
  if (v >= good) return 2;
  if (v >= warn) return 1;
  return 0;
}

int _gradeByBand(double? v,
    {required double goodLow, required double goodHigh, required double warnBand}) {
  if (v == null) return 1;
  if (v >= goodLow && v <= goodHigh) return 2;
  if ((v >= goodLow - warnBand && v < goodLow) || (v > goodHigh && v <= goodHigh + warnBand)) {
    return 1;
  }
  return 0;
}
