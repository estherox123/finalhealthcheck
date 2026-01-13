import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// IoT 및 데이터
import '../../data/iot/home_assistant_api.dart';
import '../../data/iot/home_assistant_options.dart';
import '../../data/iot/iot_repository.dart';
import '../../data/iot/device_control_controller.dart';

// 페이지 이동
import 'mirror_steps_page.dart';
import 'MIRROR_sleep_detail_page.dart';
import 'MIRROR_heart_rate_detail_page.dart';

// ✅ [추가] 회복 점수 페이지 import
import '../stress_recovery_page.dart';

import '../../widgets/top_settings_menu.dart';

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

class MirrorHomePage extends StatefulWidget {
  const MirrorHomePage({super.key});
  @override
  State<MirrorHomePage> createState() => _MirrorHomePageState();
}

class _MirrorHomePageState extends State<MirrorHomePage> {
  late final HomeAssistantApi _iotApi;
  late final DeviceControlController _iotDc;
  final ModeService _modeSvc = DummyModeService();
  Timer? _refreshTimer;

  int _sleepScore = 0;
  String _sleepStatusLabel = "-";
  Color _sleepStatusColor = Colors.grey;

  int _heartRate = 0;
  String _hrStatusLabel = "-";
  Color _hrStatusColor = Colors.grey;

  int _recoveryScore = 0;
  String _recoveryStatusLabel = "-";
  Color _recoveryStatusColor = Colors.grey;

  int _todayActivityMin = 0;
  String _activityStatusLabel = "-";
  Color _activityStatusColor = Colors.grey;

  QuickMode _mode = QuickMode.daily;
  bool _modeBusy = false;
  bool _iotReady = false;

  static const List<_NotificationItem> _lastNoti = [
    _NotificationItem(icon: Icons.air, text: '환기 필요: 공기가 탁해요', time: '10분 전', isAlert: true),
    _NotificationItem(icon: Icons.nightlight_round, text: '취침 예약 실행됨', time: '1시간 전', isAlert: false),
    _NotificationItem(icon: Icons.directions_walk, text: '걸음 목표 달성!', time: '2시간 전', isAlert: false),
  ];

  @override
  void initState() {
    super.initState();
    _initServices();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _loadHaData();
    });
  }

  void _initServices() {
    try {
      _iotApi = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
      _iotDc = DeviceControlController(IotRepository(_iotApi));
      _iotApi.preloadAllStates().then((_) {
        _iotDc.init().then((_) {
          if (mounted) {
            setState(() => _iotReady = true);
            _loadHaData();
          }
        });
      });
    } catch (e) {
      debugPrint("Mirror Init Error: $e");
    }
  }

  Future<void> _loadHaData() async {
    if (!mounted || !_iotReady) return;
    await _iotDc.init();

    final prefix = _iotApi.options.healthSensorPrefix;

    // 1. 수면
    final sleepState = await _iotApi.getState('${prefix}sleep_duration');
    double sleepMin = double.tryParse(sleepState.state) ?? 0.0;
    int sleepScore = (sleepMin / 480.0 * 100).clamp(0, 100).round();

    String sLabel = "기록 없음"; Color sColor = Colors.grey;
    if (sleepMin >= 420) { sLabel = "충분함"; sColor = Colors.green; }
    else if (sleepMin >= 300) { sLabel = "적당함"; sColor = Colors.blue; }
    else if (sleepMin > 0) { sLabel = "부족함"; sColor = Colors.orange; }

    // 2. 활동
    final stepsState = await _iotApi.getState('${prefix}daily_steps');
    double stepsVal = double.tryParse(stepsState.state) ?? 0.0;
    int activeMin = (stepsVal / 100).round();

    String aLabel = "기록 없음"; Color aColor = Colors.grey;
    if (activeMin >= 100) { aLabel = "목표 달성"; aColor = Colors.green; }
    else if (activeMin >= 60) { aLabel = "활동적"; aColor = Colors.blue; }
    else if (activeMin > 0) { aLabel = "부족함"; aColor = Colors.orange; }

    // 3. 심박수
    final hrState = await _iotApi.getState('${prefix}heart_rate');
    int lastHr = double.tryParse(hrState.state)?.round() ?? 0;

    String hLabel = "기록 없음"; Color hColor = Colors.grey;
    if (lastHr > 0) {
      if (lastHr < 60) { hLabel = "편안함"; hColor = Colors.green; }
      else if (lastHr <= 100) { hLabel = "안정"; hColor = Colors.blue; }
      else { hLabel = "높음"; hColor = Colors.redAccent; }
    }

    // 4. 회복 점수
    final recState = await _iotApi.getState('sensor.recovery_score');
    int recScore = double.tryParse(recState.state)?.round() ?? 0;

    // 임시 계산
    if (recScore == 0 && sleepMin > 0 && lastHr > 0) {
      recScore = ((sleepMin / 480 * 60) + (100 - lastHr) * 0.4).clamp(0, 100).toInt();
    }

    String rLabel = "분석 중"; Color rColor = Colors.grey;
    if (recScore >= 80) { rLabel = "회복됨"; rColor = Colors.green; }
    else if (recScore >= 60) { rLabel = "양호"; rColor = Colors.blue; }
    else if (recScore > 0) { rLabel = "주의"; rColor = Colors.orange; }

    if (mounted) {
      setState(() {
        _sleepScore = sleepScore;
        _sleepStatusLabel = sLabel; _sleepStatusColor = sColor;

        _todayActivityMin = activeMin;
        _activityStatusLabel = aLabel; _activityStatusColor = aColor;

        _heartRate = lastHr;
        _hrStatusLabel = hLabel; _hrStatusColor = hColor;

        _recoveryScore = recScore;
        _recoveryStatusLabel = rLabel; _recoveryStatusColor = rColor;
      });
    }
  }

  Future<void> _setMode(QuickMode m) async { /* 생략 */ }

  @override
  void dispose() { _refreshTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);
    final dateStr = DateFormat('M월 d일 EEEE', 'ko').format(now);

    final iotSnap = _iotDc.snapshot;
    final temp = iotSnap.livingAc.currentTemperature;
    final humidity = iotSnap.livingAc.currentHumidity;
    final co2 = iotSnap.co2;
    final pm1 = iotSnap.pm1;
    final pm25 = iotSnap.pm25;
    final pm10 = iotSnap.pm10;
    final odor = iotSnap.odor;
    final airQual = iotSnap.airQuality;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 30.0),
          children: [
            Center(
              child: Column(
                children: [
                  Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.w200, height: 1.0)),
                  const SizedBox(height: 8),
                  Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w300)),
                ],
              ),
            ),
            const SizedBox(height: 40),

            _SectionHeader(title: "TODAY'S HEALTH"),
            GridView.count(
              crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16,
              childAspectRatio: 1.6,
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              children: [
                _MirrorCard(
                  title: '수면 점수', value: _sleepScore > 0 ? "$_sleepScore" : "-", unit: "점",
                  status: _sleepStatusLabel, statusColor: _sleepStatusColor,
                  icon: Icons.bedtime, iconColor: Colors.indigoAccent,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorSleepDetailPage())),
                ),
                _MirrorCard(
                  title: '활동 시간',
                  value: _todayActivityMin > 0 ? "$_todayActivityMin" : "-",
                  unit: "분",
                  status: _activityStatusLabel, statusColor: _activityStatusColor,
                  icon: Icons.directions_walk, iconColor: Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorStepsPage())),
                ),
                _MirrorCard(
                  title: '심박수', value: _heartRate > 0 ? "$_heartRate" : "-", unit: "bpm",
                  status: _hrStatusLabel, statusColor: _hrStatusColor,
                  icon: Icons.favorite, iconColor: Colors.redAccent,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorHeartRateDetailPage())),
                ),
                _MirrorCard(
                  title: '회복 점수', value: _recoveryScore > 0 ? "$_recoveryScore" : "-", unit: "점",
                  status: _recoveryStatusLabel, statusColor: _recoveryStatusColor,
                  icon: Icons.bolt, iconColor: Colors.purpleAccent,

                  // ✅ [수정] 회복 점수 페이지 연결 (다크 모드 적용)
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => Theme(
                          data: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black, appBarTheme: const AppBarTheme(backgroundColor: Colors.black)),
                          child: const StressRecoveryPage()
                      ))
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            _SectionHeader(title: "우리 집 상태"),
            _MirrorEnvironmentFullCard(temp: temp, humidity: humidity, co2: co2, pm1: pm1, pm25: pm25, pm10: pm10, odor: odor, airQuality: airQual),
            const SizedBox(height: 32),

            _SectionHeader(title: "최근 알림", trailing: TextButton(onPressed: (){}, child: const Text("더보기", style: TextStyle(color: Colors.white70, fontSize: 16)))),
            ..._lastNoti.map((n) => _NotificationCard(item: n)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// (하단 위젯 코드는 이전과 동일하므로 생략하지 않고 그대로 사용하시면 됩니다.)
class _SectionHeader extends StatelessWidget {
  final String title; final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), if (trailing != null) trailing!]));
}

class _MirrorCard extends StatelessWidget {
  final String title; final String value; final String unit; final String status; final Color statusColor; final IconData icon; final Color iconColor; final VoidCallback onTap;
  const _MirrorCard({required this.title, required this.value, required this.unit, required this.status, required this.statusColor, required this.icon, required this.iconColor, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Padding(padding: const EdgeInsets.only(top: 4.0), child: Row(children: [Icon(icon, color: iconColor, size: 24), const SizedBox(width: 8), Flexible(child: Text(title, style: const TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))])),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text(value, style: const TextStyle(color: Colors.black87, fontSize: 36, fontWeight: FontWeight.bold)), const SizedBox(width: 4), Text(unit, style: const TextStyle(color: Colors.black45, fontSize: 14))]),
            const SizedBox(height: 2),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold))),
          ]),
        ]),
      ),
    );
  }
}

class _MirrorEnvironmentFullCard extends StatelessWidget {
  final double temp; final double humidity; final int co2; final double pm1; final double pm25; final double pm10; final int odor; final int airQuality;
  const _MirrorEnvironmentFullCard({required this.temp, required this.humidity, required this.co2, required this.pm1, required this.pm25, required this.pm10, required this.odor, required this.airQuality});
  @override
  Widget build(BuildContext context) {
    Color getStatusColor(double val, {double good=1}) => val <= good ? Colors.blueAccent : Colors.amber;
    return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: Column(children: [Row(children: [Expanded(child: _EnvBigItem(icon: Icons.thermostat, label: "온도", value: temp == 0 ? "-" : temp.toStringAsFixed(1), unit: "°C", color: Colors.redAccent)), Container(width: 1, height: 50, color: Colors.grey[200]), Expanded(child: _EnvBigItem(icon: Icons.water_drop, label: "습도", value: humidity == 0 ? "-" : humidity.round().toString(), unit: "%", color: Colors.blueAccent))]), const SizedBox(height: 20), const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)), const SizedBox(height: 20), Row(children: [Expanded(child: _EnvSmallItem(label: "통합대기", value: "${airQuality}", unit: "단계", statusColor: getStatusColor(airQuality.toDouble(), good: 1))), Expanded(child: _EnvSmallItem(label: "CO2", value: "$co2", unit: "ppm", statusColor: getStatusColor(co2.toDouble(), good: 1000))), Expanded(child: _EnvSmallItem(label: "냄새", value: "${odor}", unit: "단계", statusColor: getStatusColor(odor.toDouble(), good: 1)))]), const SizedBox(height: 16), Row(children: [Expanded(child: _EnvSmallItem(label: "초미세(1.0)", value: "${pm1.round()}", unit: "µg", statusColor: getStatusColor(pm1, good: 15))), Expanded(child: _EnvSmallItem(label: "미세(2.5)", value: "${pm25.round()}", unit: "µg", statusColor: getStatusColor(pm25, good: 15))), Expanded(child: _EnvSmallItem(label: "미세(10)", value: "${pm10.round()}", unit: "µg", statusColor: getStatusColor(pm10, good: 30)))])]));
  }
}

class _EnvBigItem extends StatelessWidget {
  final IconData icon; final String label; final String value; final String unit; final Color color;
  const _EnvBigItem({required this.icon, required this.label, required this.value, required this.unit, required this.color});
  @override Widget build(BuildContext context) => Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 20, color: Colors.grey[500]), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 15, color: Colors.grey[600], fontWeight: FontWeight.w600))]), const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0)), Padding(padding: const EdgeInsets.only(bottom: 4, left: 2), child: Text(unit, style: TextStyle(fontSize: 14, color: Colors.grey[500], fontWeight: FontWeight.w600)))])]);
}

class _EnvSmallItem extends StatelessWidget {
  final String label; final String value; final String unit; final Color statusColor;
  const _EnvSmallItem({required this.label, required this.value, required this.unit, required this.statusColor});
  @override Widget build(BuildContext context) => Column(children: [Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])), const SizedBox(height: 2), Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)), const SizedBox(width: 2), Text(unit, style: TextStyle(fontSize: 10, color: Colors.grey[500]))]), const SizedBox(height: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text("상태", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)))]);
}

class _NotificationCard extends StatelessWidget {
  final _NotificationItem item; const _NotificationCard({required this.item});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: item.isAlert ? Colors.red[50] : Colors.blue[50], shape: BoxShape.circle), child: Icon(item.icon, size: 22, color: item.isAlert ? Colors.redAccent : Colors.blueAccent)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87), maxLines: 2), const SizedBox(height: 4), Text(item.time, style: TextStyle(fontSize: 13, color: Colors.grey[500]))]))]));
}

class _NotificationItem { final IconData icon; final String text; final String time; final bool isAlert; const _NotificationItem({required this.icon, required this.text, required this.time, required this.isAlert}); }