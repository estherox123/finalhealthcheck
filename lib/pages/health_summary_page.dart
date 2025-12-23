// lib/pages/health_summary_page.dart
/// 헬스 데이터 요약 페이지 (시니어 친화적 디자인 리뉴얼)
/// - 카드형 UI, 큰 글씨, 직관적 색상/배지 적용

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
import 'heart_rate_detail_page.dart';
import 'fecal_occult_blood_page.dart';
import 'stress_recovery_page.dart';
import '../data/recovery_score.dart' as rec;
import '../reports/health_exporter.dart';
import '../reports/health_report_models.dart';
import '../reports/health_report_pdf.dart';

/// 날짜 범위
enum SummaryRange { today, week, month }

class HealthSummaryPage extends HealthStatefulPage {
  const HealthSummaryPage({super.key});

  @override
  State<HealthSummaryPage> createState() => _HealthSummaryPageState();
}

class _HealthSummaryPageState extends HealthState<HealthSummaryPage> {
  // 이 페이지에서 권한 요청/유지할 타입들
  @override
  List<HealthDataType> get types => const [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.BODY_TEMPERATURE,
  ];

  SummaryRange _range = SummaryRange.today;
  bool _loading = true;

  _SummaryModel? _data;

  @override
  void initState() {
    super.initState();
    authReady.then((_) {
      if (!mounted) return;
      _load();
    });
  }

  // ---------------- 공통 헬퍼 (기존 로직 유지) ----------------

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

  Future<Duration?> _sleepTotalInWindow(DateTime winStart, DateTime winEnd) async {
    try {
      final pts = await health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION],
        startTime: winStart,
        endTime: winEnd,
      );
      final asleep = pts.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
      final base = asleep.isNotEmpty ? asleep : pts.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();

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

  Future<double?> _avgOfType(DateTime start, DateTime end, HealthDataType t) async {
    try {
      final pts = await health.getHealthDataFromTypes(types: [t], startTime: start, endTime: end);
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

  Future<int?> _stepsBaselineNDays(int n, DateTime today0) async {
    int sum = 0, cnt = 0;
    for (int i = 1; i <= n; i++) {
      final d0 = today0.subtract(Duration(days: i));
      final d1 = d0.add(const Duration(days: 1));
      final s = await _sumSteps(d0, d1);
      if (s != null) { sum += s; cnt++; }
    }
    if (cnt == 0) return null;
    return (sum / cnt).round();
  }

  Future<Duration?> _sleepBaselineNNights(int n, DateTime today0) async {
    int sumMin = 0, cnt = 0;
    for (int i = 2; i <= n + 1; i++) {
      final anchor = today0.subtract(Duration(days: i - 1));
      final winStart = anchor.subtract(const Duration(hours: 6));
      final winEnd = anchor.add(const Duration(hours: 12));
      final dur = await _sleepTotalInWindow(winStart, winEnd);
      if (dur != null && dur.inMinutes > 0) { sumMin += dur.inMinutes; cnt++; }
    }
    if (cnt == 0) return null;
    return Duration(minutes: (sumMin / cnt).round());
  }

  int _trendArrowByMetric({required double today, required double baseline, required String metric}) {
    if (baseline <= 0) return 0;
    final ratio = (today - baseline) / baseline;
    switch (metric) {
      case 'steps': return ratio >= 0.15 ? 1 : (ratio <= -0.15 ? -1 : 0);
      case 'sleep': return ratio >= 0.10 ? 1 : (ratio <= -0.10 ? -1 : 0);
      default: return 0;
    }
  }

  Future<rec.RecoveryScore?> _loadTodayRecoveryScore(DateTime today0) async {
    if (!authorized) return null;
    final nights = <rec.NightRecoveryRaw>[];
    for (int i = 3; i >= 0; i--) {
      final anchor = today0.subtract(Duration(days: i));
      final winStart = anchor.subtract(const Duration(hours: 6));
      final winEnd = anchor.add(const Duration(hours: 12));
      final sleep = await _sleepTotalInWindow(winStart, winEnd);
      final hrMean = await _avgOfType(winStart, winEnd, HealthDataType.HEART_RATE);
      final hrv = await _avgOfType(winStart, winEnd, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
      final resp = await _avgOfType(winStart, winEnd, HealthDataType.RESPIRATORY_RATE);
      if (sleep == null && hrMean == null && hrv == null && resp == null) continue;
      nights.add(rec.NightRecoveryRaw(nightDate: anchor, hrMean: hrMean, hrvRmssd: hrv, respRate: resp, sleepTotal: sleep));
    }
    if (nights.isEmpty) return null;
    return rec.computeRecoveryFromNights(nights);
  }

  String _recoveryLabelText(rec.RecoveryLabel? label) {
    switch (label) {
      case rec.RecoveryLabel.recoveryUp: return '회복↑';
      case rec.RecoveryLabel.good: return '양호';
      case rec.RecoveryLabel.caution: return '주의';
      case rec.RecoveryLabel.needRest: return '휴식 필요';
      default: return '추정 중';
    }
  }

  _Status _recoveryLabelToStatus(rec.RecoveryLabel? label) {
    switch (label) {
      case rec.RecoveryLabel.recoveryUp:
      case rec.RecoveryLabel.good: return _Status.good;
      case rec.RecoveryLabel.caution: return _Status.warn;
      case rec.RecoveryLabel.needRest: return _Status.bad;
      default: return _Status.warn;
    }
  }

  ({DateTime nextDueAt, int daysToDue, int grade}) _calcFecalDue({required DateTime? last, int cycleDays = 90, int soonThresholdDays = 7}) {
    final today = DateTime.now();
    final base = last ?? today;
    final next = DateTime(base.year, base.month, base.day).add(Duration(days: cycleDays));
    final diff = next.difference(DateTime(today.year, today.month, today.day)).inDays;
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
    final exporter = HealthExporter(health);
    final rows = await exporter.collect(
      start: r.start, end: r.end,
      types: const [
        HealthDataType.STEPS, HealthDataType.SLEEP_SESSION, HealthDataType.SLEEP_ASLEEP,
        HealthDataType.HEART_RATE, HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC, HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_GLUCOSE, HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE, HealthDataType.BODY_MASS_INDEX,
      ],
    );
    final pdfBytes = await HealthReportPdf.build(HealthReportData(generatedAt: DateTime.now(), subjectName: '홍길동', rangeLabel: r.label, records: rows));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfPreview(build: (fmt) async => Uint8List.fromList(pdfBytes), pdfFileName: "health_report.pdf", allowPrinting: true, allowSharing: true, canChangeOrientation: false, canChangePageFormat: false)));
  }

  Future<void> _exportCsvAndShare() async {
    final r = await _currentRange();
    final exporter = HealthExporter(health);
    final rows = await exporter.collect(
      start: r.start, end: r.end,
      types: const [
        HealthDataType.STEPS, HealthDataType.SLEEP_SESSION, HealthDataType.SLEEP_ASLEEP,
        HealthDataType.HEART_RATE, HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC, HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_GLUCOSE, HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE, HealthDataType.BODY_MASS_INDEX,
      ],
    );
    final csv = HealthRecord.toCsv(rows);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/health_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csv, encoding: utf8);
    await Share.shareXFiles([XFile(file.path)], text: '${r.label} 헬스 데이터 내보내기 (CSV)');
  }

  // ---------------- Load (기존 로직 유지) ----------------
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);
      final tomorrow0 = today0.add(const Duration(days: 1));

      int? todaySteps; int? stepsAvg; int? stepsTrend; int? stepsGrade;
      Duration? sleepLastNight; Duration? sleepAvg; int? sleepTrend; int? sleepGrade;
      double? hrAvg; double? hrvAvg; double? respAvg; double? btAvg;
      rec.RecoveryScore? recovery;

      if (authorized) {
        todaySteps = await _sumSteps(today0, tomorrow0);
        if (todaySteps != null) stepsGrade = (todaySteps >= 8000 ? 2 : (todaySteps >= 4000 ? 1 : 0));

        final winStart = today0.subtract(const Duration(hours: 6));
        final winEnd = today0.add(const Duration(hours: 12));
        sleepLastNight = await _sleepTotalInWindow(winStart, winEnd);
        if (sleepLastNight != null) {
          final m = sleepLastNight.inMinutes;
          sleepGrade = (m >= 420 ? 2 : (m >= 300 ? 1 : 0));
        }

        if (_range == SummaryRange.today) {
          final sb = await _stepsBaselineNDays(7, today0);
          if (sb != null && todaySteps != null) stepsTrend = _trendArrowByMetric(today: todaySteps.toDouble(), baseline: sb.toDouble(), metric: 'steps');
          final slb = await _sleepBaselineNNights(7, today0);
          if (slb != null && sleepLastNight != null) sleepTrend = _trendArrowByMetric(today: sleepLastNight.inMinutes.toDouble(), baseline: slb.inMinutes.toDouble(), metric: 'sleep');
        } else {
          final days = _range == SummaryRange.week ? 7 : 30;
          int stepSum = 0, stepCnt = 0;
          for (int i = 0; i < days; i++) {
            final d0 = today0.subtract(Duration(days: i));
            final d1 = d0.add(const Duration(days: 1));
            final s = await _sumSteps(d0, d1);
            if (s != null) { stepSum += s; stepCnt++; }
          }
          if (stepCnt > 0) stepsAvg = (stepSum / stepCnt).round();

          int sumMin = 0, cnt = 0;
          for (int i = 0; i < days; i++) {
            final anchor = today0.subtract(Duration(days: i));
            final s = await _sleepTotalInWindow(anchor.subtract(const Duration(hours: 6)), anchor.add(const Duration(hours: 12)));
            if (s != null && s.inMinutes > 0) { sumMin += s.inMinutes; cnt++; }
          }
          if (cnt > 0) sleepAvg = Duration(minutes: (sumMin / cnt).round());
        }

        final winStartForVitals = today0.subtract(const Duration(hours: 6));
        final winEndForVitals = today0.add(const Duration(hours: 12));
        hrAvg = await _avgOfType(today0, tomorrow0, HealthDataType.HEART_RATE);
        hrvAvg = await _avgOfType(winStartForVitals, winEndForVitals, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
        respAvg = await _avgOfType(winStartForVitals, winEndForVitals, HealthDataType.RESPIRATORY_RATE);
        btAvg = await _avgOfType(winStartForVitals, winEndForVitals, HealthDataType.BODY_TEMPERATURE);

        if (_range == SummaryRange.today) recovery = await _loadTodayRecoveryScore(today0);
      }

      final DateTime? fecalLastTestAt = DateTime.now().subtract(const Duration(days: 20));
      final fecalSched = _calcFecalDue(last: fecalLastTestAt, cycleDays: 30, soonThresholdDays: 7);

      _data = _SummaryModel(
        recoveryScore: recovery?.score, recoveryLabel: recovery?.label, recoveryLowConfidence: recovery?.lowConfidence,
        stepsToday: todaySteps, stepsAvg: stepsAvg, stepsTrend: stepsTrend, stepsGrade: stepsGrade,
        sleepYesterday: sleepLastNight, sleepAvg: sleepAvg, sleepTrend: sleepTrend, sleepGrade: sleepGrade,
        hrAvg: hrAvg, hrvRmssd: hrvAvg, respRate: respAvg, bodyTempC: btAvg,
        bpSys: 122, bpDia: 78, bpGrade: 2, bpTrend: 0,
        glucoseFasting: 92, glucosePost: 128, glucoseGrade: 2, glucoseTrend: 0,
        weight: 64.4, weightDeltaKg: 0.2, weightGrade: 2, weightTrend: 0,
        urinalysisGrade: 2, urinalysisSummary: '정상',
        fecalLastTestAt: fecalLastTestAt, fecalCycleDays: 90, fecalLastResult: '잠혈 없음', fecalDueGrade: fecalSched.grade, fecalNextDueAt: fecalSched.nextDueAt, fecalDaysToDue: fecalSched.daysToDue,
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------------- UI (시니어 친화적 디자인 리뉴얼) ----------------
  @override
  Widget build(BuildContext context) {
    String rangeLabel(SummaryRange r) => switch (r) {
      SummaryRange.today => '오늘', SummaryRange.week => '7일', SummaryRange.month => '30일',
    };
    String activitySleepSectionTitle() => switch (_range) {
      SummaryRange.today => '활동 및 수면', SummaryRange.week => '최근 7일 활동·수면', SummaryRange.month => '최근 30일 활동·수면',
    };

    final appBar = AppBar(
      backgroundColor: const Color(0xFFF0F2F5),
      elevation: 0,
      title: const Text('건강 요약', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 22)),
      iconTheme: const IconThemeData(color: Colors.black87),
      actions: [
        PopupMenuButton<SummaryRange>(
          initialValue: _range,
          onSelected: (r) { setState(() => _range = r); _load(); },
          itemBuilder: (_) => [for (final r in SummaryRange.values) PopupMenuItem(value: r, child: Text(rangeLabel(r)))],
          icon: const Icon(Icons.date_range, color: Colors.black87),
          tooltip: '날짜 범위',
        ),
        IconButton(tooltip: 'PDF 보고서', icon: const Icon(Icons.picture_as_pdf), onPressed: _openPdfPreview),
        IconButton(tooltip: 'CSV 내보내기', icon: const Icon(Icons.table_view), onPressed: _exportCsvAndShare),
      ],
    );

    if (_loading || _data == null) {
      return Scaffold(backgroundColor: const Color(0xFFF0F2F5), appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    }

    final d = _data!;
    final showTrend = _range == SummaryRange.today;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            if (errorMsg != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error))),

            // 1. 회복 점수 (오늘만)
            if (_range == SummaryRange.today) ...[
              _SectionHeader('오늘 회복 상태'),
              _RecoveryCard(
                score: d.recoveryScore,
                label: _recoveryLabelText(d.recoveryLabel),
                status: _recoveryLabelToStatus(d.recoveryLabel),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StressRecoveryPage())),
              ),
              const SizedBox(height: 24),
            ],

            // 2. 활동 및 수면 (그리드)
            _SectionHeader(activitySleepSectionTitle()),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                // [활동량 카드]
                _HealthGridCard(
                  title: '활동량',
                  subtitle: _range == SummaryRange.today
                      ? (d.stepsToday == null ? '기록 없음' : '${_fmtSteps(d.stepsToday!)} 걸음')
                      : (d.stepsAvg == null ? '기록 없음' : '평균 ${_fmtSteps(d.stepsAvg!)} 걸음'),
                  status: _gradeToStatus(d.stepsGrade ?? 1),

                  // ✅ [추가] 상태 텍스트 & 게이지 (오늘 기준)
                  statusLabel: d.stepsToday != null
                      ? (d.stepsToday! >= 8000 ? '목표 달성' : (d.stepsToday! >= 4000 ? '조금 더!' : '운동 필요'))
                      : null,
                  progress: d.stepsToday != null ? (d.stepsToday! / 8000.0) : 0.0,

                  trend: d.stepsTrend ?? 0,
                  icon: Icons.directions_walk,
                  showTrend: showTrend,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StepsPage())),
                ),

                // [수면 카드]
                _HealthGridCard(
                  title: '수면',
                  subtitle: _range == SummaryRange.today
                      ? (d.sleepYesterday == null ? '기록 없음\n워치 착용 필요' : _fmtDur(d.sleepYesterday!))
                      : (d.sleepAvg == null ? '기록 없음' : '평균 ${_fmtDur(d.sleepAvg!)}'),
                  status: _gradeToStatus(d.sleepGrade ?? 1),

                  // 상태 텍스트 & 게이지 (오늘 기준)
                  statusLabel: d.sleepYesterday != null
                      ? (d.sleepYesterday!.inMinutes >= 420 ? '충분함' : (d.sleepYesterday!.inMinutes >= 300 ? '적당함' : '부족함'))
                      : null,
                  progress: d.sleepYesterday != null ? (d.sleepYesterday!.inMinutes / 480.0) : 0.0, // 8시간 목표

                  trend: d.sleepTrend ?? 0,
                  icon: Icons.bedtime,
                  showTrend: showTrend,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepDetailPage())),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 3. 바이탈 (그리드)
            const _SectionHeader('바이탈'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _HealthGridCard(
                  title: '심박수',
                  subtitle: (d.hrAvg == null) ? '기록 없음\n워치 착용 필요' : '${d.hrAvg!.toStringAsFixed(0)} bpm',
                  status: _gradeToStatus(_gradeByRange(d.hrAvg, low: 50, high: 90)),
                  trend: 0, icon: Icons.monitor_heart, showTrend: false,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeartRateDetailPage())),
                ),
                _HealthGridCard(
                  title: '스트레스',
                  subtitle: (d.hrvRmssd == null) ? '기록 없음\n워치 착용 필요' : '${d.hrvRmssd!.toStringAsFixed(0)} ms',
                  status: _gradeToStatus(_gradeByThresholdUpBetter(d.hrvRmssd, good: 50, warn: 30)),
                  trend: 0, icon: Icons.multiline_chart, showTrend: false,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StressRecoveryPage())),
                ),
                _HealthGridCard(
                  title: '호흡수',
                  subtitle: (d.respRate == null) ? '기록 없음' : '${d.respRate!.toStringAsFixed(1)} rpm',
                  status: _gradeToStatus(_gradeByBand(d.respRate, goodLow: 12, goodHigh: 18, warnBand: 2)),
                  trend: 0, icon: Icons.air, showTrend: false,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '호흡수'))),
                ),
                _HealthGridCard(
                  title: '체온',
                  subtitle: (d.bodyTempC == null) ? '기록 없음' : '${d.bodyTempC!.toStringAsFixed(1)} °C',
                  status: _gradeToStatus(_gradeByBand(d.bodyTempC, goodLow: 36.0, goodHigh: 37.2, warnBand: .3)),
                  trend: 0, icon: Icons.device_thermostat, showTrend: false,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '체온'))),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 4. 검사 결과 (가로형 리스트)
            const _SectionHeader('검사 결과'),
            _HealthListCard(
              title: '혈압', subtitle: '${d.bpSys}/${d.bpDia} mmHg', status: _gradeToStatus(d.bpGrade),
              icon: Icons.favorite_outline, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '혈압'))),
            ),
            _HealthListCard(
              title: '혈당', subtitle: '식전 ${d.glucoseFasting} / 식후 ${d.glucosePost}', status: _gradeToStatus(d.glucoseGrade),
              icon: Icons.bloodtype_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '혈당'))),
            ),
            _HealthListCard(
              title: '체중', subtitle: '${d.weight.toStringAsFixed(1)} kg', status: _gradeToStatus(d.weightGrade),
              icon: Icons.monitor_weight_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '체중'))),
            ),
            _HealthListCard(
              title: '소변검사', subtitle: d.urinalysisSummary, status: _gradeToStatus(d.urinalysisGrade),
              icon: Icons.science_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '소변검사'))),
            ),
            _HealthListCard(
              title: '대변검사', subtitle: '다음 검사까지 ${d.fecalDaysToDue}일', status: _gradeToStatus(d.fecalDueGrade),
              icon: Icons.event_repeat_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FecalOccultBloodPage())),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static String _fmtSteps(int v) => NumberFormat('#,###').format(v);
  static String _fmtDur(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return '${h}시간 ${m}분';
  }
  static _Status _gradeToStatus(int g) => switch (g) { 2 => _Status.good, 1 => _Status.warn, _ => _Status.bad };
}

/// 상태 등급
enum _Status { good, warn, bad }

// ---------------- UI 컴포넌트 (시니어 친화적) ----------------

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }
}

// 1. 회복 점수 카드 (가로형 대형)
class _RecoveryCard extends StatelessWidget {
  final int? score;
  final String label;
  final _Status status;
  final VoidCallback onTap;

  const _RecoveryCard({required this.score, required this.label, required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.bolt, color: color, size: 24), const SizedBox(width: 8), Text('회복 점수', style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w600))]),
                const SizedBox(height: 8),
                Text(score != null ? '$score' : '-', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            )
          ],
        ),
      ),
    );
  }
}

// 2. 그리드형 카드
class _HealthGridCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final _Status status;
  final String? statusLabel;
  final double? progress;
  final int trend;
  final IconData icon;
  final bool showTrend;
  final VoidCallback? onTap;

  const _HealthGridCard({
    required this.title,
    required this.subtitle,
    required this.status,
    this.statusLabel,
    this.progress,
    required this.trend,
    required this.icon,
    this.showTrend = true,
    required this.onTap,
  });

  static final RegExp _numRe = RegExp(r'(\d[\d,]*(?:\.\d+)?)');

  List<TextSpan> _parseSubtitle(String text) {
    if (!_numRe.hasMatch(text)) {
      return [
        TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600], // 너무 연하지 않게 진한 회색
            height: 1.3,
          ),
        )
      ];
    }

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final m in _numRe.allMatches(text)) {
      if (m.start > cursor) spans.add(TextSpan(text: text.substring(cursor, m.start), style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)));
      spans.add(TextSpan(text: m.group(0), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black87)));
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor), style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 상단: 아이콘 + 제목
            Row(children: [Icon(icon, size: 20, color: color), const SizedBox(width: 8), Flexible(child: Text(title, style: TextStyle(fontSize: 15, color: Colors.grey[700], fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))]),

            // 하단: 수치 + 게이지 + 배지
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(text: TextSpan(children: _parseSubtitle(subtitle))),
                const SizedBox(height: 8),

                // 게이지와 상태 텍스트 표시 영역
                if (progress != null || statusLabel != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (progress != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress!.clamp(0.0, 1.0),
                            backgroundColor: color.withOpacity(0.15),
                            color: color,
                            minHeight: 6,
                          ),
                        ),
                      if (statusLabel != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6)
                              ),
                              child: Text(statusLabel!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                            ),
                            const Spacer(),
                            if (showTrend && trend != 0)
                              Icon(trend > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18, color: Colors.grey[400])
                          ],
                        )
                      ]
                    ],
                  )
                else if (showTrend && trend != 0)
                // 게이지 없을 때 기존 화살표 유지
                  Icon(trend > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 20, color: Colors.grey[400])
              ],
            )
          ],
        ),
      ),
    );
  }
}

// 3. 리스트형 카드 (검사 결과) - 가로로 김
class _HealthListCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final _Status status;
  final IconData icon;
  final VoidCallback? onTap;

  const _HealthListCard({required this.title, required this.subtitle, required this.status, required this.icon, required this.onTap});

  static final RegExp _numRe = RegExp(r'(\d[\d,]*(?:\.\d+)?)');

  List<TextSpan> _parseSubtitle(String text) {
    final spans = <TextSpan>[];
    int cursor = 0;
    for (final m in _numRe.allMatches(text)) {
      if (m.start > cursor) spans.add(TextSpan(text: text.substring(cursor, m.start), style: const TextStyle(fontSize: 14, color: Colors.grey)));
      spans.add(TextSpan(text: m.group(0), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87))); // 리스트는 약간 작게(20)
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor), style: const TextStyle(fontSize: 14, color: Colors.grey)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 22, color: color)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    RichText(text: TextSpan(children: _parseSubtitle(subtitle))),
                  ],
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _Status status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final text = status == _Status.good ? '정상' : (status == _Status.warn ? '주의' : '위험');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

Color _statusColor(_Status s) => switch (s) { _Status.good => Colors.green, _Status.warn => Colors.orange, _Status.bad => Colors.redAccent };

// ... (기존 _SummaryModel, _WipPage, 등급 계산 헬퍼 함수들은 아래에 그대로 유지) ...

/// -------- 데이터 컨테이너 (기존 유지) --------
class _SummaryModel {
  final int? recoveryScore; final rec.RecoveryLabel? recoveryLabel; final bool? recoveryLowConfidence;
  final int? stepsToday; final int? stepsAvg; final int? stepsTrend; final int? stepsGrade;
  final Duration? sleepYesterday; final Duration? sleepAvg; final int? sleepTrend; final int? sleepGrade;
  final double? hrAvg; final double? hrvRmssd; final double? respRate; final double? bodyTempC;
  final int bpSys; final int bpDia; final int bpGrade; final int bpTrend;
  final int glucoseFasting; final int glucosePost; final int glucoseGrade; final int glucoseTrend;
  final double weight; final double weightDeltaKg; final int weightGrade; final int weightTrend;
  final int urinalysisGrade; final String urinalysisSummary;
  final DateTime? fecalLastTestAt; final int fecalCycleDays; final String fecalLastResult; final int fecalDueGrade; final DateTime fecalNextDueAt; final int fecalDaysToDue;

  const _SummaryModel({
    required this.recoveryScore, required this.recoveryLabel, required this.recoveryLowConfidence,
    required this.stepsToday, required this.stepsAvg, required this.stepsTrend, required this.stepsGrade,
    required this.sleepYesterday, required this.sleepAvg, required this.sleepTrend, required this.sleepGrade,
    required this.hrAvg, required this.hrvRmssd, required this.respRate, required this.bodyTempC,
    required this.bpSys, required this.bpDia, required this.bpGrade, required this.bpTrend,
    required this.glucoseFasting, required this.glucosePost, required this.glucoseGrade, required this.glucoseTrend,
    required this.weight, required this.weightDeltaKg, required this.weightGrade, required this.weightTrend,
    required this.urinalysisGrade, required this.urinalysisSummary,
    required this.fecalLastTestAt, required this.fecalCycleDays, required this.fecalLastResult, required this.fecalDueGrade, required this.fecalNextDueAt, required this.fecalDaysToDue,
  });
}

class _WipPage extends StatelessWidget {
  final String title;
  const _WipPage({required this.title, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: Text('개발중', style: TextStyle(fontSize: 18))));
}

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

int _gradeByBand(double? v, {required double goodLow, required double goodHigh, required double warnBand}) {
  if (v == null) return 1;
  if (v >= goodLow && v <= goodHigh) return 2;
  if ((v >= goodLow - warnBand && v < goodLow) || (v > goodHigh && v <= goodHigh + warnBand)) return 1;
  return 0;
}