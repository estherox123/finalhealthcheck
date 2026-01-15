import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// IoT 및 데이터
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';
import '../../data/iot/iot_repository.dart';
import '../../data/iot/device_control_controller.dart';
import '../../data/recovery_score.dart' as rec;

// 미러용 상세 페이지
import 'MIRROR_sleep_detail_page.dart';
import 'mirror_steps_page.dart';
import 'MIRROR_heart_rate_detail_page.dart';
import 'MIRROR_stress_recovery_page.dart'; // ✅ 미러 전용 회복 페이지 연결
import 'MIRROR_inbody_page.dart';

// 기타 페이지 (모바일용 재사용 - 추후 미러용 제작 필요)
import '../blood_pressure_page.dart';

class MirrorHealthSummaryPage extends StatefulWidget {
  const MirrorHealthSummaryPage({super.key});
  @override
  State<MirrorHealthSummaryPage> createState() => _MirrorHealthSummaryPageState();
}

class _MirrorHealthSummaryPageState extends State<MirrorHealthSummaryPage> {
  late final HomeAssistantApi _iotApi;
  late final DeviceControlController _haController;
  bool _loading = true;
  Timer? _refreshTimer;

  int? _recoveryScore;
  rec.RecoveryLabel? _recoveryLabel;
  int? _stepsToday;
  Duration? _sleepYesterday;
  int? _heartRate;
  double? _weight;
  double? _bodyFat;
  int? _bpSys;
  int? _bpDia;
  int? _glucose;

  @override
  void initState() {
    super.initState();
    _initServices();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) { if (mounted) _loadHaData(); });
  }

  void _initServices() {
    try {
      _iotApi = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
      final repo = IotRepository(_iotApi);
      _haController = DeviceControlController(repo);
      _iotApi.preloadAllStates().then((_) {
        _haController.init().then((_) {
          if (mounted) _loadHaData();
        });
      });
    } catch (e) {
      debugPrint("Mirror Init Error: $e");
    }
  }

  Future<void> _loadHaData() async {
    // (로딩 중 화면 깜빡임 방지를 위해 setState 최소화)
    try {
      await _haController.init();
      final prefix = _iotApi.options.healthSensorPrefix;

      final sleepState = await _iotApi.getState('${prefix}sleep_duration');
      final sleepMin = double.tryParse(sleepState.state)?.toInt() ?? 0;
      final sleepDuration = sleepMin > 0 ? Duration(minutes: sleepMin) : null;

      final stepsState = await _iotApi.getState('${prefix}daily_steps');
      final steps = double.tryParse(stepsState.state)?.toInt();

      final hrState = await _iotApi.getState('${prefix}heart_rate');
      final hr = double.tryParse(hrState.state)?.toInt();

      final weightState = await _iotApi.getState('${prefix}weight');
      double? weightVal = double.tryParse(weightState.state);
      if (weightVal != null && weightVal > 1000) weightVal /= 1000.0;

      final fatState = await _iotApi.getState('${prefix}body_fat');
      final bodyFat = double.tryParse(fatState.state);

      final sysState = await _iotApi.getState('${prefix}systolic_blood_pressure');
      final diaState = await _iotApi.getState('${prefix}diastolic_blood_pressure');
      final sys = double.tryParse(sysState.state)?.toInt();
      final dia = double.tryParse(diaState.state)?.toInt();

      final gluState = await _iotApi.getState('${prefix}blood_glucose');
      final glucose = double.tryParse(gluState.state)?.toInt();

      final recState = await _iotApi.getState('sensor.recovery_score');
      int? recScore = double.tryParse(recState.state)?.toInt();

      if ((recScore == null || recScore == 0) && sleepMin > 0 && hr != null) {
        recScore = ((sleepMin / 480 * 60) + (100 - hr) * 0.4).clamp(0, 100).toInt();
      }

      rec.RecoveryLabel recLabel = rec.RecoveryLabel.caution;
      if (recScore != null) {
        if (recScore >= 80) recLabel = rec.RecoveryLabel.recoveryUp;
        else if (recScore >= 60) recLabel = rec.RecoveryLabel.good;
        else if (recScore >= 40) recLabel = rec.RecoveryLabel.caution;
        else recLabel = rec.RecoveryLabel.needRest;
      }

      if (mounted) {
        setState(() {
          _sleepYesterday = sleepDuration;
          _stepsToday = steps;
          _heartRate = hr;
          _weight = weightVal;
          _bodyFat = bodyFat;
          _bpSys = sys;
          _bpDia = dia;
          _glucose = glucose;
          _recoveryScore = recScore;
          _recoveryLabel = recLabel;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("HA Load Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _refreshTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_loading && _recoveryScore == null) {
      return Scaffold(backgroundColor: Colors.black, body: const Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    final weightInfo = _analyzeWeightStatus(weight: _weight, bodyFat: _bodyFat);
    final bpInfo = (_bpSys != null && _bpDia != null) ? _analyzeBP(_bpSys!, _bpDia!) : (label: '기록 없음', status: _Status.warn);
    final hrInfo = _heartRate != null ? _analyzeHR(_heartRate!) : (label: '기록 없음', status: _Status.warn);
    final glucoseInfo = _glucose != null ? _analyzeGlucose(_glucose!) : (label: '기록 없음', status: _Status.warn);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // ✅ 폰트 UP
        title: const Text('건강 요약', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white, size: 30), onPressed: _loadHaData)
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHaData,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          children: [
            _SectionHeader('오늘 회복 상태'),
            _RecoveryCard(
              score: _recoveryScore,
              label: _recoveryLabelText(_recoveryLabel),
              status: _recoveryLabelToStatus(_recoveryLabel),
              // ✅ 미러 전용 회복 페이지로 연결
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorStressRecoveryPage())),
            ),
            const SizedBox(height: 40),

            _SectionHeader('활동 및 수면'),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5, mainAxisSpacing: 20, crossAxisSpacing: 20,
              children: [
                _HealthGridCard(
                  title: '활동량', value: _stepsToday != null ? NumberFormat('#,###').format(_stepsToday) : '-', unit: _stepsToday != null ? '걸음' : null,
                  status: (_stepsToday ?? 0) >= 5000 ? _Status.good : _Status.warn, statusLabel: _stepsToday != null ? ((_stepsToday! >= 5000) ? '목표 달성' : '운동 필요') : null,
                  progress: (_stepsToday ?? 0) / 8000.0, icon: Icons.directions_walk,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorStepsPage())),
                ),
                _HealthGridCard(
                  title: '수면', value: _sleepYesterday != null ? '${_sleepYesterday!.inHours}시간 ${_sleepYesterday!.inMinutes % 60}분' : '-', unit: null,
                  status: (_sleepYesterday?.inHours ?? 0) >= 6 ? _Status.good : _Status.warn, statusLabel: _sleepYesterday != null ? ((_sleepYesterday!.inHours >= 6) ? '충분함' : '부족함') : null,
                  progress: (_sleepYesterday?.inMinutes ?? 0) / 480.0, icon: Icons.bedtime,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorSleepDetailPage())),
                ),
              ],
            ),
            const SizedBox(height: 40),

            _SectionHeader('주요 바이탈'),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5, mainAxisSpacing: 20, crossAxisSpacing: 20,
              children: [
                _HealthGridCard(
                  title: '심박수', value: _heartRate != null ? '$_heartRate' : '-', unit: _heartRate != null ? 'bpm' : null,
                  status: hrInfo.status, statusLabel: hrInfo.label, progress: _heartRate != null ? (_heartRate! / 150) : 0.0, icon: Icons.monitor_heart,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorHeartRateDetailPage())),
                ),
                _HealthGridCard(
                  title: '체중', value: _weight != null ? _weight!.toStringAsFixed(1) : '-', unit: _weight != null ? 'kg' : null,
                  status: weightInfo.status, statusLabel: weightInfo.label, icon: Icons.monitor_weight_outlined,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Theme(data: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black, appBarTheme: const AppBarTheme(backgroundColor: Colors.black)), child: const MirrorInBodyPage()))),
                ),
                _HealthGridCard(
                  title: '혈압', value: (_bpSys != null) ? '$_bpSys/$_bpDia' : '-', unit: (_bpSys != null) ? 'mmHg' : null,
                  status: bpInfo.status, statusLabel: bpInfo.label, icon: Icons.favorite_outline,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Theme(data: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black, appBarTheme: const AppBarTheme(backgroundColor: Colors.black)), child: const BloodPressurePage()))),
                ),
                _HealthGridCard(
                  title: '혈당', value: _glucose != null ? '$_glucose' : '-', unit: _glucose != null ? 'mg/dL' : null,
                  status: glucoseInfo.status, statusLabel: glucoseInfo.label, progress: null, icon: Icons.bloodtype_outlined,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '혈당'))),
                ),
              ],
            ),
            const SizedBox(height: 40),

            _SectionHeader('정기 검사'),
            _HealthListCard(title: '소변검사 (7일 주기)', subtitle: '기록 없음', status: _Status.warn, tagText: '검사 필요', icon: Icons.science_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WipPage(title: '소변검사')))),
            _HealthListCard(title: '대변검사 (10일 주기)', subtitle: '기록 없음', status: _Status.warn, tagText: '검사 필요', icon: Icons.event_repeat_outlined, onTap: (){}),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _recoveryLabelText(rec.RecoveryLabel? label) {
    switch (label) { case rec.RecoveryLabel.recoveryUp: return '회복됨'; case rec.RecoveryLabel.good: return '양호'; case rec.RecoveryLabel.caution: return '주의'; case rec.RecoveryLabel.needRest: return '휴식 필요'; default: return '분석 중'; }
  }
  _Status _recoveryLabelToStatus(rec.RecoveryLabel? label) {
    switch (label) { case rec.RecoveryLabel.recoveryUp: case rec.RecoveryLabel.good: return _Status.good; case rec.RecoveryLabel.caution: return _Status.warn; case rec.RecoveryLabel.needRest: return _Status.bad; default: return _Status.warn; }
  }
  ({String label, _Status status}) _analyzeWeightStatus({double? weight, double? bodyFat}) {
    if (weight == null) return (label: '기록 없음', status: _Status.warn);
    if (bodyFat != null && bodyFat > 0) {
      if (bodyFat < 18) return (label: '체지방 낮음', status: _Status.warn);
      if (bodyFat <= 28) return (label: '체지방 표준', status: _Status.good);
      if (bodyFat <= 35) return (label: '경도 비만', status: _Status.warn);
      return (label: '비만', status: _Status.bad);
    }
    return (label: '체중 측정됨', status: _Status.good);
  }
  ({String label, _Status status}) _analyzeBP(int sys, int dia) { if (sys < 120 && dia < 80) return (label: '정상', status: _Status.good); if (sys < 140 && dia < 90) return (label: '주의', status: _Status.warn); return (label: '고혈압', status: _Status.bad); }
  ({String label, _Status status}) _analyzeGlucose(int val) { if (val < 70) return (label: '저혈당', status: _Status.bad); if (val <= 140) return (label: '정상', status: _Status.good); return (label: '주의', status: _Status.warn); }
  ({String label, _Status status}) _analyzeHR(int val) { if (val < 50) return (label: '낮음', status: _Status.warn); if (val <= 90) return (label: '안정', status: _Status.good); return (label: '높음', status: _Status.bad); }
}

enum _Status { good, warn, bad }
Color _statusColor(_Status s) => switch (s) { _Status.good => Colors.green, _Status.warn => Colors.orange, _Status.bad => Colors.redAccent };

class _SectionHeader extends StatelessWidget {
  final String text; const _SectionHeader(this.text, {super.key});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16, left: 4), child: Text(text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)));
}

class _RecoveryCard extends StatelessWidget {
  final int? score; final String label; final _Status status; final VoidCallback onTap;
  const _RecoveryCard({required this.score, required this.label, required this.status, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
            padding: const EdgeInsets.all(28), // 패딩 확대
            decoration: BoxDecoration(
                color: Colors.grey[900], // ✅ 배경: 어두운 회색
                borderRadius: BorderRadius.circular(24)
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Icon(Icons.bolt, color: color, size: 32), const SizedBox(width: 12), Text('회복 점수', style: TextStyle(fontSize: 20, color: Colors.grey[400], fontWeight: FontWeight.bold))]), // ✅ 폰트 UP & 색상 조정
                        const SizedBox(height: 12),
                        Text(score != null ? '$score' : '-', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)) // ✅ 폰트 UP
                      ]
                  ),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                      child: Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)) // ✅ 폰트 UP
                  )
                ]
            )
        )
    );
  }
}

class _HealthGridCard extends StatelessWidget {
  final String title; final String value; final String? unit; final _Status status; final String? statusLabel; final double? progress; final IconData icon; final VoidCallback? onTap;
  const _HealthGridCard({required this.title, required this.value, this.unit, required this.status, this.statusLabel, this.progress, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
            color: Colors.grey[900], // ✅ 배경: 어두운 회색
            borderRadius: BorderRadius.circular(24)
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(width: 10),
            Flexible(child: Text(title, style: TextStyle(fontSize: 18, color: Colors.grey[400], fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)) // ✅ 폰트 UP & 색상 조정
          ]),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)), // ✅ 폰트 UP & 흰색
              if (unit != null) ...[const SizedBox(width: 6), Text(unit!, style: TextStyle(fontSize: 16, color: Colors.grey[500], fontWeight: FontWeight.w600))]
            ]),
            const SizedBox(height: 6),
            if (statusLabel != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(statusLabel!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
            if (progress != null) ...[const SizedBox(height: 8), SizedBox(width: 120, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress!.clamp(0.0, 1.0), backgroundColor: color.withOpacity(0.15), color: color, minHeight: 8)))] // 바 두께 UP
          ])))
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
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22), decoration: BoxDecoration(
        color: Colors.grey[900], // ✅ 배경: 어두운 회색
        borderRadius: BorderRadius.circular(20)
    ), child: Row(children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 26, color: color)),
      const SizedBox(width: 20),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 16, color: Colors.grey[400], fontWeight: FontWeight.bold)), // ✅ 폰트 UP
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)) // ✅ 폰트 UP & 흰색
      ])),
      if (tagText != null) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(tagText!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)))
    ]))));
  }
}

class _WipPage extends StatelessWidget {
  final String title; const _WipPage({required this.title, super.key});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(title: Text(title, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)), body: const Center(child: Text('개발중', style: TextStyle(fontSize: 20, color: Colors.white))));
}