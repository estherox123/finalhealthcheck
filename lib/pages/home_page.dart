// lib/pages/home_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import 'mirror/MIRROR_home_page.dart';

import 'sleep_detail_page.dart';
import 'heart_rate_detail_page.dart';
import 'steps_page.dart';
import 'stress_recovery_page.dart';

import '../controllers/dashboard_controller.dart';
import '../data/health_repository.dart';
import '../widgets/permission_banner.dart';
import '../widgets/top_settings_menu.dart';
import '../data/recovery_score.dart' as rec;

import '../data/iot/device_control_controller.dart';
import '../data/iot/iot_repository.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';

// ===== QuickMode & ModeService =====
enum QuickMode { sleep, rest, daily }

abstract class ModeService {
  Future<void> apply(QuickMode mode);
}

class DummyModeService implements ModeService {
  @override
  Future<void> apply(QuickMode mode) async {
    await Future.delayed(const Duration(milliseconds: 150));
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Health _health = Health();

  // ✅ [수정 1] const 제거 (HealthDataType 에러 방지) 및 MOVE_MINUTES 제거
  // EXERCISE_TIME도 없다면 이 줄을 지우세요. 보통 EXERCISE_TIME은 있습니다.
  List<HealthDataType> get types => [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.WEIGHT,
    HealthDataType.EXERCISE_TIME, // MOVE_MINUTES 대체
  ];

  int _sleepScore = 0;
  String _sleepStatusLabel = "분석 중";
  Color _sleepStatusColor = Colors.grey;

  int _heartRate = 0;
  String _hrStatusLabel = "분석 중";
  Color _hrStatusColor = Colors.grey;

  int _recoveryScore = 0;
  String _recoveryStatusLabel = "분석 중";
  Color _recoveryStatusColor = Colors.grey;

  int _todayActivityMin = 0;
  String _activityStatusLabel = "분석 중";
  Color _activityStatusColor = Colors.grey;

  static const List<_NotificationItem> _lastNoti = [
    _NotificationItem(icon: Icons.air, text: '환기 필요: 공기가 탁해요', time: '10분 전', isAlert: true),
    _NotificationItem(icon: Icons.nightlight_round, text: '취침 예약 실행됨', time: '1시간 전', isAlert: false),
    _NotificationItem(icon: Icons.directions_walk, text: '걸음 목표 달성!', time: '2시간 전', isAlert: false),
  ];

  late final DashboardController _dc;
  late final DeviceControlController _iotDc;
  late final HomeAssistantApi _iotApi; // HA API 직접 접근용
  final ModeService _modeSvc = DummyModeService();

  Timer? _refreshTimer;
  QuickMode _mode = QuickMode.daily;
  bool _modeBusy = false;
  bool _hasPermission = false;
  bool _iotReady = false; // IoT 초기화 여부 체크

  @override
  void initState() {
    super.initState();

    _dc = DashboardController(HealthRepositoryImpl());
    _dc.addListener(_onRefreshUI);
    _dc.init();

    try {
      _iotApi = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
      _iotDc = DeviceControlController(IotRepository(_iotApi));
      _iotDc.addListener(_onRefreshUI);
      _iotDc.init().then((_) {
        if(mounted) setState(() => _iotReady = true);
      });
    } catch (e) {
      debugPrint('IoT Init Error: $e');
    }

    _checkPermissionsAndLoad();

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _iotDc.init();
        _loadSyncedHealthData();
      }
    });
  }

  void _onRefreshUI() {
    if (mounted) setState(() {});
  }

  Future<void> _checkPermissionsAndLoad() async {
    await [Permission.activityRecognition, Permission.location].request();
    try {
      bool authorized = await _health.requestAuthorization(types);
      if (authorized) {
        setState(() => _hasPermission = true);
        await _loadSyncedHealthData();
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    }
  }

  double? _numVal(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  // ✅ [수정 2] getState 에러 해결을 위해 _iotReady 체크 및 try-catch 보강
  Future<double> _getDataOrFallback({
    required Future<double?> Function() healthFetcher,
    required String haEntityId,
    bool useFallback = false,
  }) async {
    try {
      double? val = await healthFetcher();
      if (val != null && val > 0) return val;
    } catch (_) {}

    if (useFallback && _iotReady) {
      try {
        // HomeAssistantApi에 getState 메서드가 추가되어야 함 (위 1번 단계 참조)
        final stateObj = await _iotApi.getState(haEntityId);
        final val = double.tryParse(stateObj.state);
        if (val != null) return val;
      } catch (e) {
        debugPrint("HA Fallback Error ($haEntityId): $e");
      }
    }
    return 0.0;
  }

  // ... (기존 _sleepTotalInWindow, _avgOfType, _loadTodayRecoveryScore 유지)
  Future<Duration?> _sleepTotalInWindow(DateTime s, DateTime e) async {
    try {
      final pts = await _health.getHealthDataFromTypes(types: const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION], startTime: s, endTime: e);
      final sessions = pts.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();
      int minSum = 0;
      if (sessions.isNotEmpty) {
        for (var p in sessions) minSum += p.dateTo.difference(p.dateFrom).inMinutes;
      } else {
        final asleep = pts.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
        for (var p in asleep) minSum += p.dateTo.difference(p.dateFrom).inMinutes;
      }
      return minSum > 0 ? Duration(minutes: minSum) : null;
    } catch (_) { return null; }
  }

  Future<double?> _avgOfType(DateTime start, DateTime end, HealthDataType t) async {
    try {
      final pts = await _health.getHealthDataFromTypes(types: [t], startTime: start, endTime: end);
      final vals = pts.map((p) => _numVal(p.value)).whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    } catch (_) { return null; }
  }

  Future<rec.RecoveryScore?> _loadTodayRecoveryScore(DateTime today0) async {
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


  Future<void> _loadSyncedHealthData() async {
    try {
      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);

      bool isMirror = false;
      if (mounted) isMirror = MediaQuery.of(context).size.width > 600;

      // 1. 수면
      final sleepStart = today0.subtract(const Duration(hours: 6));
      final sleepEnd = today0.add(const Duration(hours: 12));
      double sleepMinVal = await _getDataOrFallback(
        healthFetcher: () async {
          final d = await _sleepTotalInWindow(sleepStart, sleepEnd);
          return d?.inMinutes.toDouble();
        },
        haEntityId: 'sensor.sleep_duration_minutes',
        useFallback: isMirror,
      );
      final int sleepMin = sleepMinVal.toInt();
      final int sleepScore = (sleepMin / 480.0 * 100).clamp(0, 100).round();
      final double sleepHours = sleepMin / 60.0;
      String sleepLabel = sleepMin == 0 ? "기록 없음" : (sleepHours >= 7 ? "충분함" : (sleepHours >= 5 ? "적당함" : "부족함"));
      Color sleepColor = sleepMin == 0 ? Colors.grey : (sleepHours >= 7 ? Colors.green : (sleepHours >= 5 ? Colors.blue : Colors.orange));

      // 2. 활동 (EXERCISE_TIME 사용, 없으면 0) -> HA 대체
      // 사용자가 요청한 steps 센서 로직 반영 (raw steps / 100 = approx min)
      double activeMinVal = await _getDataOrFallback(
        healthFetcher: () async {
          final data = await _health.getHealthDataFromTypes(types: [HealthDataType.EXERCISE_TIME], startTime: today0, endTime: now);
          if (data.isEmpty) return 0.0;
          double sum = 0;
          for(var d in data) sum += _numVal(d.value) ?? 0;
          return sum;
        },
        haEntityId: 'sensor.sm_s931n_daily_steps', // HA 센서 (Steps raw 값)
        useFallback: isMirror,
      );

      // HA 센서(steps)를 가져왔을 경우 100으로 나누어 분으로 환산하는 로직이 필요함
      // activeMinVal이 Health에서 왔다면 이미 '분' 단위일 것이고,
      // HA에서 'Steps'를 가져왔다면 아주 큰 숫자(예: 5000)일 것임.
      // 간단한 휴리스틱: 값이 1000을 넘으면 스텝으로 간주하고 나누기
      if (activeMinVal > 1000) {
        activeMinVal = activeMinVal / 100;
      }

      final int activeMin = activeMinVal.round();
      String actLabel = activeMin == 0 ? "기록 없음" : (activeMin >= 60 ? "활동적" : (activeMin >= 30 ? "적당함" : "부족함"));
      Color actColor = activeMin == 0 ? Colors.grey : (activeMin >= 60 ? Colors.green : (activeMin >= 30 ? Colors.blue : Colors.orange));

      // 3. 심박수
      double hrVal = await _getDataOrFallback(
        healthFetcher: () async {
          final hrData = await _health.getHealthDataFromTypes(types: [HealthDataType.HEART_RATE], startTime: now.subtract(const Duration(hours: 24)), endTime: now);
          hrData.sort((a, b) => b.dateTo.compareTo(a.dateTo));
          return hrData.isNotEmpty ? _numVal(hrData.first.value) : null;
        },
        haEntityId: 'sensor.heart_rate_latest',
        useFallback: isMirror,
      );
      int lastHr = hrVal.round();
      String hrLabel = lastHr == 0 ? "기록 없음" : (lastHr < 60 ? "편안함" : (lastHr <= 100 ? "안정" : "높음"));
      Color hrColor = lastHr == 0 ? Colors.grey : (lastHr < 60 ? Colors.green : (lastHr <= 100 ? Colors.blue : Colors.redAccent));

      // 4. 회복 점수
      final recovery = await _loadTodayRecoveryScore(today0);
      int recScore = recovery?.score ?? 0;
      String recLabel = "분석 중";
      Color recColor = Colors.grey;

      if (isMirror && recovery == null && _iotReady) {
        try {
          final haRec = await _iotApi.getState('sensor.recovery_score');
          recScore = double.tryParse(haRec.state)?.round() ?? 0;
          if (recScore > 0) { recLabel = "HA 데이터"; recColor = Colors.blue; }
        } catch (_) {}
      } else if (recovery != null) {
        switch (recovery.label) {
          case rec.RecoveryLabel.recoveryUp: recLabel = "회복됨"; recColor = Colors.green; break;
          case rec.RecoveryLabel.good: recLabel = "양호"; recColor = Colors.green; break;
          case rec.RecoveryLabel.caution: recLabel = "주의"; recColor = Colors.orange; break;
          case rec.RecoveryLabel.needRest: recLabel = "휴식 필요"; recColor = Colors.redAccent; break;
          default: recLabel = "분석 중"; recColor = Colors.grey;
        }
      } else { recLabel = "기록 없음"; }

      if (mounted) {
        setState(() {
          _sleepScore = sleepScore; _sleepStatusLabel = sleepLabel; _sleepStatusColor = sleepColor;
          _todayActivityMin = activeMin; _activityStatusLabel = actLabel; _activityStatusColor = actColor;
          _heartRate = lastHr; _hrStatusLabel = hrLabel; _hrStatusColor = hrColor;
          _recoveryScore = recScore; _recoveryStatusLabel = recLabel; _recoveryStatusColor = recColor;
        });
      }
    } catch (e) { debugPrint("Sync Load Error: $e"); }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _dc.removeListener(_onRefreshUI);
    _iotDc.removeListener(_onRefreshUI);
    super.dispose();
  }

  Future<void> _setMode(QuickMode m) async {
    if (_modeBusy || _mode == m) return;
    final prev = _mode;
    setState(() { _mode = m; _modeBusy = true; });
    try {
      await _modeSvc.apply(m);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_modeName(m)} 모드로 변경했습니다.'), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating));
    } catch (_) {
      if (!mounted) return;
      setState(() => _mode = prev);
    } finally {
      if (mounted) setState(() => _modeBusy = false);
    }
  }

  String _modeName(QuickMode m) {
    switch (m) { case QuickMode.sleep: return '수면'; case QuickMode.rest: return '휴식'; case QuickMode.daily: return '일상'; }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 600) return const MirrorHomePage(); // 미러 페이지로 이동

    // ... (이하 Scaffold 및 기존 모바일 UI 코드 동일)
    // 기존 코드의 build 부분을 그대로 유지하세요.
    // _EnvBigItem, _EnvSmallItem 등 컴포넌트도 그대로 둡니다.

    // (간략화를 위해 build 내부 생략, 위에서 작성한 logic이 핵심입니다)
    // 원래 코드의 build() 메소드 내용을 그대로 사용하면 됩니다.

    // 아래는 build 메서드 구현부를 다시 적어드립니다 (복사 붙여넣기 편하게)
    final now = DateTime.now();
    final dateStr = DateFormat('M월 d일 EEEE', 'ko').format(now);
    final greet = _greeting(now);
    final loading = _dc.status == DashboardStatus.loading;
    final iotSnap = _iotDc.snapshot;
    double temp = iotSnap.livingAc.currentTemperature;
    double humidity = iotSnap.livingAc.currentHumidity;
    int co2 = iotSnap.co2;
    double pm1 = iotSnap.pm1;
    double pm25 = iotSnap.pm25;
    double pm10 = iotSnap.pm10;
    int odor = iotSnap.odor;
    int airQual = iotSnap.airQuality;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F2F5), elevation: 0,
        title: const Text("건강 대시보드", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: const [TopSettingsMenu(), SizedBox(width: 8)],
        bottom: loading ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator(minHeight: 4)) : null,
      ),
      body: RefreshIndicator(
        onRefresh: () async { await Future.wait([_dc.refresh(), _iotDc.init(), _loadSyncedHealthData()]); },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            if (!_hasPermission) Padding(padding: const EdgeInsets.only(bottom: 20), child: PermissionBanner(types: types, onGranted: () async => _checkPermissionsAndLoad())),
            const SizedBox(height: 10),
            Text(greet, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.3, color: Colors.black87)),
            const SizedBox(height: 8),
            Text(dateStr, style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w500)),
            const SizedBox(height: 30),
            _SectionHeader(title: '오늘의 컨디션'),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.1,
              children: [
                _HealthCard(title: '수면 점수', value: _sleepScore.toString(), unit: '점', icon: Icons.bedtime, iconColor: Colors.indigoAccent, statusColor: _sleepStatusColor, statusLabel: _sleepStatusLabel, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepDetailPage()))),
                _HealthCard(title: '심박수', value: _heartRate.toString(), unit: 'bpm', icon: Icons.favorite, iconColor: Colors.redAccent, statusColor: _hrStatusColor, statusLabel: _hrStatusLabel, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeartRateDetailPage()))),
                _HealthCard(title: '회복 점수', value: _recoveryScore.toString(), unit: '점', icon: Icons.bolt, iconColor: Colors.purpleAccent, statusColor: _recoveryStatusColor, statusLabel: _recoveryStatusLabel, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StressRecoveryPage()))),
                _HealthCard(title: '활동 시간', value: _todayActivityMin < 60 ? "$_todayActivityMin" : "${_todayActivityMin ~/ 60}", unit: _todayActivityMin < 60 ? "분" : "시간 ${_todayActivityMin % 60}분", icon: Icons.directions_run, iconColor: Colors.orange, statusColor: _activityStatusColor, statusLabel: _activityStatusLabel, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StepsPage()))),
              ],
            ),
            const SizedBox(height: 32),
            _SectionHeader(title: '우리 집 상태'),
            _EnvironmentFullCard(temp: temp, humidity: humidity, co2: co2, pm1: pm1, pm25: pm25, pm10: pm10, odor: odor, airQuality: airQual),
            const SizedBox(height: 32),
            _SectionHeader(title: '모드 변경'),
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]), child: Row(children: [Expanded(child: _ModeToggleBtn(label: '수면', icon: Icons.bedtime_rounded, isSelected: _mode == QuickMode.sleep, onTap: () => _setMode(QuickMode.sleep))), Expanded(child: _ModeToggleBtn(label: '휴식', icon: Icons.spa_rounded, isSelected: _mode == QuickMode.rest, onTap: () => _setMode(QuickMode.rest))), Expanded(child: _ModeToggleBtn(label: '일상', icon: Icons.wb_sunny_rounded, isSelected: _mode == QuickMode.daily, onTap: () => _setMode(QuickMode.daily)))])),
            const SizedBox(height: 32),
            _SectionHeader(title: '최근 알림', trailing: TextButton(onPressed: (){}, child: const Text("더보기", style: TextStyle(fontSize: 16)))),
            ..._lastNoti.map((n) => _NotificationCard(item: n)),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}


// ------------------------------ 컴포넌트 ------------------------------

({Color color, String label}) _getAirStatus(String type, double val) {
  if (type == 'PM10') {
    if (val <= 30) return (color: Colors.blueAccent, label: '좋음');
    if (val <= 80) return (color: Colors.green, label: '보통');
    if (val <= 150) return (color: Colors.amber, label: '나쁨');
    return (color: Colors.redAccent, label: '매우나쁨');
  } else if (type == 'PM2.5' || type == 'PM1.0') {
    if (val <= 15) return (color: Colors.blueAccent, label: '좋음');
    if (val <= 35) return (color: Colors.green, label: '보통');
    if (val <= 75) return (color: Colors.amber, label: '나쁨');
    return (color: Colors.redAccent, label: '매우나쁨');
  } else if (type == 'CO2') {
    if (val <= 1000) return (color: Colors.blueAccent, label: '좋음');
    if (val <= 1500) return (color: Colors.green, label: '보통');
    if (val <= 3000) return (color: Colors.amber, label: '나쁨');
    return (color: Colors.redAccent, label: '매우나쁨');
  } else if (type == 'GAS' || type == 'AirQuality') {
    int level = val.toInt();
    if (level <= 1) return (color: Colors.blueAccent, label: '좋음');
    if (level == 2) return (color: Colors.green, label: '보통');
    if (level == 3) return (color: Colors.amber, label: '나쁨');
    return (color: Colors.redAccent, label: '매우나쁨');
  }
  return (color: Colors.grey, label: '-');
}

void _showGuideDialog(BuildContext context, String title) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$title 기준", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text("🟦 파랑 (좋음)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 4),
            _buildGuideText(title, 0),
            const SizedBox(height: 12),
            const Text("🟩 초록 (보통)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 4),
            _buildGuideText(title, 1),
            const SizedBox(height: 12),
            const Text("🟨 노랑 (나쁨)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber)),
            const SizedBox(height: 4),
            _buildGuideText(title, 2),
            const SizedBox(height: 12),
            const Text("🟥 빨강 (매우나쁨)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            const SizedBox(height: 4),
            _buildGuideText(title, 3),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black87, elevation: 0),
                child: const Text("확인"),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildGuideText(String type, int level) {
  String text = "";
  if (type.contains("PM10")) {
    const refs = ["30 이하", "31 ~ 80", "81 ~ 150", "151 이상"];
    text = "${refs[level]} µg/m³";
  } else if (type.contains("초미세") || type.contains("미세(2.5)")) {
    const refs = ["15 이하", "16 ~ 35", "36 ~ 75", "76 이상"];
    text = "${refs[level]} µg/m³";
  } else if (type.contains("이산화탄소")) {
    const refs = ["1,000 이하", "1,001 ~ 1,500", "1,501 ~ 3,000", "3,001 이상"];
    text = "${refs[level]} ppm";
  } else {
    const refs = ["좋음", "보통", "나쁨", "매우나쁨"];
    text = refs[level];
  }
  return Text(text, style: TextStyle(fontSize: 14, color: Colors.grey[700]));
}

class _EnvironmentFullCard extends StatelessWidget {
  final double temp; final double humidity;
  final int co2; final double pm1; final double pm25; final double pm10;
  final int odor; final int airQuality;

  const _EnvironmentFullCard({
    required this.temp, required this.humidity,
    required this.co2, required this.pm1, required this.pm25, required this.pm10,
    required this.odor, required this.airQuality,
  });

  @override
  Widget build(BuildContext context) {
    final stQual = _getAirStatus('AirQuality', airQuality.toDouble());
    final stCo2 = _getAirStatus('CO2', co2.toDouble());
    final stOdor = _getAirStatus('GAS', odor.toDouble());
    final stPm1 = _getAirStatus('PM1.0', pm1);
    final stPm25 = _getAirStatus('PM2.5', pm25);
    final stPm10 = _getAirStatus('PM10', pm10);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))]),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _EnvBigItem(icon: Icons.thermostat, label: "온도", value: temp == 0 ? "-" : temp.toStringAsFixed(1), unit: "°C", color: Colors.redAccent)),
              Container(width: 1, height: 50, color: Colors.grey[200]),
              Expanded(child: _EnvBigItem(icon: Icons.water_drop, label: "습도", value: humidity == 0 ? "-" : humidity.round().toString(), unit: "%", color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(child: _EnvSmallItem(label: "통합대기", value: stQual.label, unit: "", statusColor: stQual.color, onTap: () => _showGuideDialog(context, "통합대기"))),
              Expanded(child: _EnvSmallItem(label: "이산화탄소", value: "$co2", unit: "ppm", statusColor: stCo2.color, onTap: () => _showGuideDialog(context, "이산화탄소"))),
              Expanded(child: _EnvSmallItem(label: "냄새강도", value: stOdor.label, unit: "", statusColor: stOdor.color, onTap: () => _showGuideDialog(context, "냄새(GAS)"))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _EnvSmallItem(label: "초미세(1.0)", value: "${pm1.round()}", unit: "µg", statusColor: stPm1.color, onTap: () => _showGuideDialog(context, "초미세먼지(PM1.0)"))),
              Expanded(child: _EnvSmallItem(label: "미세(2.5)", value: "${pm25.round()}", unit: "µg", statusColor: stPm25.color, onTap: () => _showGuideDialog(context, "미세먼지(PM2.5)"))),
              Expanded(child: _EnvSmallItem(label: "미세(10)", value: "${pm10.round()}", unit: "µg", statusColor: stPm10.color, onTap: () => _showGuideDialog(context, "미세먼지(PM10)"))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title; final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)), if (trailing != null) trailing!]));
}

class _HealthCard extends StatelessWidget {
  final String title; final String value; final String unit; final IconData icon; final Color iconColor; final Color statusColor; final String statusLabel; final VoidCallback? onTap;
  const _HealthCard({required this.title, required this.value, required this.unit, required this.icon, required this.iconColor, required this.statusColor, required this.statusLabel, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Icon(icon, size: 20, color: iconColor), const SizedBox(width: 8), Flexible(child: Text(title, style: TextStyle(fontSize: 15, color: Colors.grey[700], fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))]), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text(value, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0)), const SizedBox(width: 4), Flexible(child: Text(unit, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500)))]), const SizedBox(height: 8), Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text(statusLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: statusColor)))])])])));
}

class _EnvBigItem extends StatelessWidget {
  final IconData icon; final String label; final String value; final String unit; final Color color;
  const _EnvBigItem({required this.icon, required this.label, required this.value, required this.unit, required this.color});
  @override Widget build(BuildContext context) => Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 20, color: Colors.grey[500]), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 15, color: Colors.grey[600], fontWeight: FontWeight.w600))]), const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0)), Padding(padding: const EdgeInsets.only(bottom: 4, left: 2), child: Text(unit, style: TextStyle(fontSize: 14, color: Colors.grey[500], fontWeight: FontWeight.w600)))])]);
}

class _EnvSmallItem extends StatelessWidget {
  final String label; final String value; final String unit; final Color statusColor; final VoidCallback? onTap;
  const _EnvSmallItem({required this.label, required this.value, required this.unit, required this.statusColor, this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Column(children: [Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])), const SizedBox(height: 2), Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)), const SizedBox(width: 2), Text(unit, style: TextStyle(fontSize: 10, color: Colors.grey[500]))]), const SizedBox(height: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(statusColor == Colors.blueAccent ? "좋음" : (statusColor == Colors.green ? "보통" : (statusColor == Colors.amber ? "나쁨" : "매우나쁨")), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)))]));
}

class _ModeToggleBtn extends StatelessWidget {
  final String label; final IconData icon; final bool isSelected; final VoidCallback onTap;
  const _ModeToggleBtn({required this.label, required this.icon, required this.isSelected, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: isSelected ? Colors.indigoAccent : Colors.transparent, borderRadius: BorderRadius.circular(16)), child: Column(children: [Icon(icon, color: isSelected ? Colors.white : Colors.grey[400], size: 28), const SizedBox(height: 6), Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey[600]))])));
}

class _NotificationCard extends StatelessWidget {
  final _NotificationItem item; const _NotificationCard({required this.item});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: item.isAlert ? Colors.red[50] : Colors.blue[50], shape: BoxShape.circle), child: Icon(item.icon, size: 22, color: item.isAlert ? Colors.redAccent : Colors.blueAccent)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87), maxLines: 2), const SizedBox(height: 4), Text(item.time, style: TextStyle(fontSize: 13, color: Colors.grey[500]))]))]));
}

class _NotificationItem { final IconData icon; final String text; final String time; final bool isAlert; const _NotificationItem({required this.icon, required this.text, required this.time, required this.isAlert}); }
String _greeting(DateTime now) { final h = now.hour; if (h < 6) return '편안한 밤\n보내고 계신가요? 🌙'; if (h < 11) return '상쾌한 아침,\n건강을 챙겨보세요 ☀️'; if (h < 18) return '나른한 오후,\n스트레칭 어때요? 🌿'; return '오늘 하루도\n고생 많으셨어요 ✨'; }