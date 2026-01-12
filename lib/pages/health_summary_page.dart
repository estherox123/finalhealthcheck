// lib/pages/health_summary_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_health_page.dart';
import 'sleep_detail_page.dart';
import 'steps_page.dart';
import 'heart_rate_detail_page.dart';
import 'fecal_occult_blood_page.dart';
import 'stress_recovery_page.dart';
import 'inbody_page.dart';
import 'blood_pressure_page.dart';
import '../data/recovery_score.dart' as rec;
import '../reports/health_exporter.dart';
import '../reports/health_report_models.dart';
import '../reports/health_report_pdf.dart';

import '../data/iot/device_control_controller.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';
import '../data/iot/iot_repository.dart';

/// 날짜 범위
enum SummaryRange { today, week, month }

class HealthSummaryPage extends HealthStatefulPage {
  const HealthSummaryPage({super.key});

  @override
  State<HealthSummaryPage> createState() => _HealthSummaryPageState();
}

class _HealthSummaryPageState extends HealthState<HealthSummaryPage> {
  late final DeviceControlController _haController;

  // ignore: unused_field
  bool _haReady = false;

  @override
  List<HealthDataType> get types => const [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.WEIGHT,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
  ];

  SummaryRange _range = SummaryRange.today;
  bool _loading = true;
  _SummaryModel? _data;

  @override
  void initState() {
    super.initState();
    final api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    final repo = IotRepository(api);
    _haController = DeviceControlController(repo);
    _haController.addListener(_onHaUpdate);

    authReady.then((_) {
      if (!mounted) return;
      _loadAllData();
    });
  }

  void _onHaUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _haController.removeListener(_onHaUpdate);
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      await health.requestAuthorization(types);
      await Future.wait([
        _haController.init(),
        _loadPhoneDataInternal(),
      ]);
      _haReady = true;
    } catch (e) {
      debugPrint("Data Load Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPhoneDataInternal() async {
    try {
      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);
      final tomorrow0 = today0.add(const Duration(days: 1));

      int? todaySteps;
      Duration? sleepLastNight;
      rec.RecoveryScore? recovery;

      try {
        final steps = await health.getTotalStepsInInterval(today0, tomorrow0);
        todaySteps = steps;
      } catch (_) {}

      final sleepEnd = today0.add(const Duration(hours: 12));
      final sleepStart = today0.subtract(const Duration(hours: 6));
      sleepLastNight = await _sleepTotalInWindow(sleepStart, sleepEnd);

      if (_range == SummaryRange.today) recovery = await _loadTodayRecoveryScore(today0);

      double? glucose = await _fetchLatest(HealthDataType.BLOOD_GLUCOSE);
      final glucoseInfo = glucose != null
          ? _analyzeGlucose(glucose.toInt())
          : (label: '기록 없음', status: _Status.warn);

      final fecalStore = FecalLocalStore();
      final fecalHistory = await fecalStore.loadHistory();
      final fecalLast = fecalHistory.isNotEmpty ? fecalHistory.first : null;
      final fecalCycle = _calcCycleStatus(fecalLast?.date, 10);
      _Status finalFecalStatus = fecalCycle.status;
      if (fecalLast?.result == FecalResult.suspect) finalFecalStatus = _Status.bad;

      final prefs = await SharedPreferences.getInstance();
      final urineStr = prefs.getString('urine_last_date');
      final urineDate = urineStr != null ? DateTime.tryParse(urineStr) : null;
      final urineResultStr = prefs.getString('urine_last_result') ?? '기록 없음';
      final urineCycle = _calcCycleStatus(urineDate, 7);

      _data = _SummaryModel(
        recoveryScore: recovery?.score,
        recoveryLabel: recovery?.label,
        recoveryLowConfidence: recovery?.lowConfidence,
        stepsToday: todaySteps,
        sleepYesterday: sleepLastNight,
        glucoseVal: glucose?.toInt(),
        glucoseStatus: (glucose != null) ? glucoseInfo.status : _Status.warn,
        glucoseLabel: (glucose != null) ? glucoseInfo.label : null,
        fecalLastDate: fecalLast?.date,
        fecalResultText: fecalLast?.result == FecalResult.suspect ? '잠혈 의심' : (fecalLast == null ? '기록 없음' : '잠혈 없음'),
        fecalTagText: fecalCycle.tagText,
        fecalStatus: finalFecalStatus,
        urineLastDate: urineDate,
        urineResultText: urineDate == null ? '기록 없음' : urineResultStr,
        urineTagText: urineCycle.tagText,
        urineStatus: urineCycle.status,
      );
    } catch (e) {
      debugPrint("Phone Data Internal Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _data == null) {
      return Scaffold(
          backgroundColor: const Color(0xFFF0F2F5),
          appBar: AppBar(title: const Text('건강 요약')),
          body: const Center(child: CircularProgressIndicator())
      );
    }

    final d = _data!;
    final haSnap = _haController.snapshot;

    // [체중]
    final weightVal = haSnap.inbodyWeight > 0 ? haSnap.inbodyWeight : null;
    final weightInfo = _analyzeWeightStatus(weight: weightVal, bodyFat: haSnap.inbodyPBF, directBmi: haSnap.inbodyBMI);

    // [혈압]
    final sys = haSnap.bpSystolic > 0 ? haSnap.bpSystolic.toInt() : null;
    final dia = haSnap.bpDiastolic > 0 ? haSnap.bpDiastolic.toInt() : null;
    final bpInfo = (sys != null && dia != null)
        ? _analyzeBP(sys, dia)
        : (label: '기록 없음', status: _Status.warn);

    // [심박수]
    final hrVal = haSnap.bpPulse > 0 ? haSnap.bpPulse : null;
    final hrInfo = hrVal != null
        ? _analyzeHR(hrVal)
        : (label: '기록 없음', status: _Status.warn);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('건강 요약', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: const Color(0xFFF0F2F5), elevation: 0, iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAllData
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. 회복 점수
            _SectionHeader('오늘 회복 상태'),
            _RecoveryCard(
              score: d.recoveryScore,
              label: _recoveryLabelText(d.recoveryLabel),
              status: _recoveryLabelToStatus(d.recoveryLabel),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StressRecoveryPage())),
            ),
            const SizedBox(height: 24),

            // 2. 활동 및 수면
            _SectionHeader('활동 및 수면'),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1, mainAxisSpacing: 12, crossAxisSpacing: 12,
              children: [
                _HealthGridCard(
                  title: '활동량',
                  value: d.stepsToday != null ? NumberFormat('#,###').format(d.stepsToday) : '기록 없음',
                  unit: d.stepsToday != null ? '걸음' : null, // ✅ 단위 분리
                  status: (d.stepsToday ?? 0) >= 5000 ? _Status.good : _Status.warn,
                  statusLabel: d.stepsToday != null ? ((d.stepsToday! >= 5000) ? '목표 달성' : '운동 필요') : null,
                  progress: (d.stepsToday ?? 0) / 8000.0,
                  icon: Icons.directions_walk,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StepsPage())),
                ),
                _HealthGridCard(
                  title: '수면',
                  value: d.sleepYesterday != null ? '${d.sleepYesterday!.inHours}시간 ${d.sleepYesterday!.inMinutes % 60}분' : '기록 없음',
                  unit: null, // 수면은 단위가 섞여 있어 그대로 둠
                  status: (d.sleepYesterday?.inHours ?? 0) >= 6 ? _Status.good : _Status.warn,
                  statusLabel: d.sleepYesterday != null ? ((d.sleepYesterday!.inHours >= 6) ? '충분함' : '부족함') : null,
                  progress: (d.sleepYesterday?.inMinutes ?? 0) / 480.0,
                  icon: Icons.bedtime,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepDetailPage())),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 3. 주요 바이탈
            _SectionHeader('주요 바이탈'),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1, mainAxisSpacing: 12, crossAxisSpacing: 12,
              children: [
                _HealthGridCard(
                  title: '심박수',
                  value: hrVal != null ? '${hrVal.round()}' : '기록 없음',
                  unit: hrVal != null ? 'bpm' : null, // ✅ 단위 분리
                  status: hrInfo.status,
                  statusLabel: hrInfo.label,
                  progress: hrVal != null ? (hrVal / 150) : 0.0,
                  icon: Icons.monitor_heart,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeartRateDetailPage())),
                ),
                _HealthGridCard(
                  title: '체중',
                  value: weightVal != null ? weightVal.toStringAsFixed(1) : '기록 없음',
                  unit: weightVal != null ? 'kg' : null, // ✅ 단위 분리
                  status: weightInfo.status,
                  statusLabel: weightInfo.label,
                  icon: Icons.monitor_weight_outlined,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InBodyPage())),
                ),
                _HealthGridCard(
                  title: '혈압',
                  value: (sys != null) ? '$sys/$dia' : '기록 없음',
                  unit: (sys != null) ? 'mmHg' : null, // ✅ 단위 분리
                  status: bpInfo.status,
                  statusLabel: bpInfo.label,
                  icon: Icons.favorite_outline,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BloodPressurePage())),
                ),
                _HealthGridCard(
                  title: '혈당',
                  value: d.glucoseVal != null ? '${d.glucoseVal}' : '기록 없음',
                  unit: d.glucoseVal != null ? 'mg/dL' : null, // ✅ 단위 분리
                  status: d.glucoseStatus,
                  statusLabel: d.glucoseLabel,
                  progress: null,
                  icon: Icons.bloodtype_outlined,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '혈당'))),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 4. 정기 검사
            _SectionHeader('정기 검사'),
            _HealthListCard(
              title: '소변검사 (7일 주기)',
              subtitle: d.urineResultText,
              status: d.urineStatus,
              tagText: d.urineTagText,
              icon: Icons.science_outlined,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '소변검사 (Licote 연동 예정)'))),
            ),
            _HealthListCard(
              title: '대변검사 (10일 주기)',
              subtitle: d.fecalResultText,
              status: d.fecalStatus,
              tagText: d.fecalTagText,
              icon: Icons.event_repeat_outlined,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FecalOccultBloodPage())),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Helper Functions (그대로 유지)
  double? _numVal(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue?.toDouble();
    return null;
  }

  Future<double?> _fetchLatest(HealthDataType type) async {
    try {
      final now = DateTime.now();
      int days = 30;
      if (type == HealthDataType.HEART_RATE || type == HealthDataType.BLOOD_GLUCOSE) days = 2;

      final data = await health.getHealthDataFromTypes(
          types: [type],
          startTime: now.subtract(Duration(days: days)),
          endTime: now
      );
      if (data.isEmpty) return null;
      data.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      return _numVal(data.first.value);
    } catch (_) { return null; }
  }

  Future<Duration?> _sleepTotalInWindow(DateTime winStart, DateTime winEnd) async {
    try {
      final pts = await health.getHealthDataFromTypes(types: const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION], startTime: winStart, endTime: winEnd);
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
    } catch (_) { return null; }
  }

  Future<double?> _avgOfType(DateTime start, DateTime end, HealthDataType t) async {
    try {
      final pts = await health.getHealthDataFromTypes(types: [t], startTime: start, endTime: end);
      final vals = pts.map((p) => _numVal(p.value)).whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    } catch (_) { return null; }
  }

  Future<rec.RecoveryScore?> _loadTodayRecoveryScore(DateTime today0) async {
    if (!authorized) return null;
    final nights = <rec.NightRecoveryRaw>[];
    for (int i = 10; i >= 0; i--) {
      final anchor = today0.subtract(Duration(days: i));
      final winStart = anchor.subtract(const Duration(hours: 6));
      final winEnd = anchor.add(const Duration(hours: 12));
      final sleep = await _sleepTotalInWindow(winStart, winEnd);
      final hrMean = await _avgOfType(winStart, winEnd, HealthDataType.HEART_RATE);
      final hrv = await _avgOfType(winStart, winEnd, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
      final resp = await _avgOfType(winStart, winEnd, HealthDataType.RESPIRATORY_RATE);
      if (sleep == null && hrMean == null) continue;
      nights.add(rec.NightRecoveryRaw(nightDate: anchor, hrMean: hrMean, hrvRmssd: hrv, respRate: resp, sleepTotal: sleep));
    }
    return nights.isEmpty ? null : rec.computeRecoveryFromNights(nights);
  }

  String _recoveryLabelText(rec.RecoveryLabel? label) {
    switch (label) {
      case rec.RecoveryLabel.recoveryUp: return '회복됨';
      case rec.RecoveryLabel.good: return '양호';
      case rec.RecoveryLabel.caution: return '주의';
      case rec.RecoveryLabel.needRest: return '휴식 필요';
      default: return '분석 중';
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

  ({String label, _Status status}) _analyzeWeightStatus({double? weight, double? heightM, double? directBmi, double? bodyFat}) {
    if (weight == null) return (label: '기록 없음', status: _Status.warn);
    if (bodyFat != null && bodyFat > 0) {
      if (bodyFat < 18) return (label: '체지방 낮음', status: _Status.warn);
      if (bodyFat <= 28) return (label: '체지방 표준', status: _Status.good);
      if (bodyFat <= 35) return (label: '경도 비만', status: _Status.warn);
      return (label: '비만', status: _Status.bad);
    }
    double? bmi = directBmi;
    if (bmi == null && heightM != null && heightM > 0) bmi = weight / (heightM * heightM);
    if (bmi == null) return (label: '체중 측정됨', status: _Status.good);
    if (bmi < 18.5) return (label: '저체중', status: _Status.warn);
    if (bmi < 23) return (label: '정상', status: _Status.good);
    if (bmi < 25) return (label: '과체중', status: _Status.warn);
    return (label: '비만', status: _Status.bad);
  }

  ({String label, _Status status}) _analyzeBP(int sys, int dia) {
    if (sys < 120 && dia < 80) return (label: '정상', status: _Status.good);
    if (sys < 140 && dia < 90) return (label: '주의', status: _Status.warn);
    return (label: '고혈압', status: _Status.bad);
  }

  ({String label, _Status status}) _analyzeGlucose(int val) {
    if (val < 70) return (label: '저혈당', status: _Status.bad);
    if (val <= 140) return (label: '정상', status: _Status.good);
    if (val <= 200) return (label: '주의', status: _Status.warn);
    return (label: '고혈당', status: _Status.bad);
  }

  ({String label, _Status status}) _analyzeHR(double val) {
    if (val < 50) return (label: '낮음', status: _Status.warn);
    if (val <= 90) return (label: '안정', status: _Status.good);
    if (val <= 110) return (label: '약간 높음', status: _Status.warn);
    return (label: '높음', status: _Status.bad);
  }

  ({String tagText, _Status status}) _calcCycleStatus(DateTime? lastDate, int cycleDays) {
    if (lastDate == null) return (tagText: '검사 필요', status: _Status.bad);
    final diff = DateTime.now().difference(lastDate).inDays;
    final remain = cycleDays - diff;
    if (remain < 0) return (tagText: '검사 필요', status: _Status.bad);
    return (tagText: 'D-$remain', status: remain <= 2 ? _Status.warn : _Status.good);
  }
}

class _SummaryModel {
  final int? recoveryScore; final rec.RecoveryLabel? recoveryLabel; final bool? recoveryLowConfidence;
  final int? stepsToday; final Duration? sleepYesterday;
  final int? glucoseVal; final _Status glucoseStatus; final String? glucoseLabel;
  final DateTime? urineLastDate; final String urineResultText; final String urineTagText; final _Status urineStatus;
  final DateTime? fecalLastDate; final String fecalResultText; final String fecalTagText; final _Status fecalStatus;

  const _SummaryModel({
    required this.recoveryScore, required this.recoveryLabel, required this.recoveryLowConfidence,
    required this.stepsToday, required this.sleepYesterday,
    required this.glucoseVal, required this.glucoseStatus, required this.glucoseLabel,
    required this.urineLastDate, required this.urineResultText, required this.urineTagText, required this.urineStatus,
    required this.fecalLastDate, required this.fecalResultText, required this.fecalTagText, required this.fecalStatus,
  });
}

// ---------------- UI Widgets ----------------
enum _Status { good, warn, bad }
Color _statusColor(_Status s) => switch (s) { _Status.good => Colors.green, _Status.warn => Colors.orange, _Status.bad => Colors.redAccent };

class _SectionHeader extends StatelessWidget {
  final String text; const _SectionHeader(this.text, {super.key});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)));
}

class _RecoveryCard extends StatelessWidget {
  final int? score; final String label; final _Status status; final VoidCallback onTap;
  const _RecoveryCard({required this.score, required this.label, required this.status, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.bolt, color: color, size: 24), const SizedBox(width: 8), Text('회복 점수', style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w600))]), const SizedBox(height: 8), Text(score != null ? '$score' : '-', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0))]), Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)))])));
  }
}

// ✅ [수정] GridCard도 값(Value)과 단위(Unit)를 분리하여 표시
class _HealthGridCard extends StatelessWidget {
  final String title;
  final String value; // 수정: 전체 문자열 대신 값만 받음
  final String? unit; // 추가: 단위
  final _Status status;
  final String? statusLabel;
  final double? progress;
  final IconData icon;
  final VoidCallback? onTap;

  const _HealthGridCard({
    required this.title,
    required this.value,
    this.unit,
    required this.status,
    this.statusLabel,
    this.progress,
    required this.icon,
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [Icon(icon, size: 20, color: color), const SizedBox(width: 8), Flexible(child: Text(title, style: TextStyle(fontSize: 15, color: Colors.grey[700], fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ✅ 값과 단위를 분리해서 표시 (값은 크고 진하게, 단위는 작게)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black87)),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(unit!, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                ]
              ],
            ),
            const SizedBox(height: 8),
            if (statusLabel != null)
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(statusLabel!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color))),
              ]),
            if (progress != null) ...[
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress!.clamp(0.0, 1.0), backgroundColor: color.withOpacity(0.15), color: color, minHeight: 6)),
            ]
          ])
        ]),
      ),
    );
  }
}

class _HealthListCard extends StatelessWidget {
  final String title; final String subtitle; final _Status status; final String? tagText; final IconData icon; final VoidCallback? onTap;
  const _HealthListCard({required this.title, required this.subtitle, required this.status, this.tagText, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 22, color: color)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87))])), if (tagText != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(tagText!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)))]))));
  }
}

class _WipPage extends StatelessWidget {
  final String title; const _WipPage({required this.title, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: Text('개발중', style: TextStyle(fontSize: 18))));
}