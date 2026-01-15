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
import 'MIRROR_stress_recovery_page.dart'; // ✅ 미러 전용 회복 페이지

class MirrorHomePage extends StatefulWidget {
  const MirrorHomePage({super.key});
  @override
  State<MirrorHomePage> createState() => _MirrorHomePageState();
}

class _MirrorHomePageState extends State<MirrorHomePage> {
  late final HomeAssistantApi _iotApi;
  late final DeviceControlController _iotDc;

  Timer? _refreshTimer;

  // 건강 상태 변수들
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

  bool _iotReady = false;

  static const List<_NotificationItem> _lastNoti = [
    _NotificationItem(icon: Icons.air, text: '환기 필요: 공기가 탁해요', time: '10분 전', isAlert: true),
    _NotificationItem(icon: Icons.nightlight_round, text: '취침 예약 실행됨', time: '1시간 전', isAlert: false),
    _NotificationItem(icon: Icons.directions_walk, text: '걸음 목표 달성!', time: '2시간 전', isAlert: false),
  ];

  @override
  void initState() {
    super.initState();
    _initIotServices();

    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && _iotReady) {
        _loadHaData();
      }
    });
  }

  void _initIotServices() async {
    try {
      final options = HomeAssistantOptions.fromEnv();
      _iotApi = HomeAssistantApi(options: options);

      final repo = IotRepository(_iotApi);
      _iotDc = DeviceControlController(repo);

      await _iotApi.preloadAllStates();
      await _iotDc.init();

      if (mounted) {
        setState(() => _iotReady = true);
        _loadHaData();
      }
    } catch (e) {
      debugPrint("Mirror IoT Init Error: $e");
    }
  }

  Future<void> _loadHaData() async {
    if (!_iotReady) return;

    try {
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

      // 2. 활동량
      final stepsState = await _iotApi.getState('${prefix}daily_steps');
      double stepsVal = double.tryParse(stepsState.state) ?? 0.0;
      int activeMin = (stepsVal / 100).round();

      String aLabel = "기록 없음"; Color aColor = Colors.grey;
      if (activeMin >= 100) { aLabel = "목표 달성"; aColor = Colors.green; }
      else if (activeMin >= 50) { aLabel = "활동적"; aColor = Colors.blue; }
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

      if (recScore == 0 && sleepMin > 0 && lastHr > 0) {
        recScore = ((sleepMin / 480 * 60) + (100 - lastHr) * 0.4).clamp(0, 100).toInt();
      }

      String rLabel = "분석 중"; Color rColor = Colors.grey;
      if (recScore >= 80) { rLabel = "회복됨"; rColor = Colors.green; }
      else if (recScore >= 60) { rLabel = "양호"; rColor = Colors.blue; }
      else if (recScore > 0) { rLabel = "주의"; rColor = Colors.orange; }

      if (mounted) {
        setState(() {
          _sleepScore = sleepScore; _sleepStatusLabel = sLabel; _sleepStatusColor = sColor;
          _todayActivityMin = activeMin; _activityStatusLabel = aLabel; _activityStatusColor = aColor;
          _heartRate = lastHr; _hrStatusLabel = hLabel; _hrStatusColor = hColor;
          _recoveryScore = recScore; _recoveryStatusLabel = rLabel; _recoveryStatusColor = rColor;
        });
      }
    } catch (e) {
      debugPrint("HA Data Load Error: $e");
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_iotReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final iotSnap = _iotDc.snapshot;
    final temp = iotSnap.livingAc.currentTemperature;
    final humidity = iotSnap.livingAc.currentHumidity;
    final co2 = iotSnap.co2;
    final pm1 = iotSnap.pm1;
    final pm25 = iotSnap.pm25;
    final pm10 = iotSnap.pm10;
    final odor = iotSnap.odor;
    final airQual = iotSnap.airQuality;

    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);
    final dateStr = DateFormat('M월 d일 EEEE', 'ko').format(now);

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
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MirrorStressRecoveryPage()
                      )
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            _SectionHeader(title: "우리 집 상태"),
            _MirrorEnvironmentFullCard(
                temp: temp, humidity: humidity,
                co2: co2, pm1: pm1, pm25: pm25, pm10: pm10,
                odor: odor, airQuality: airQual
            ),
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

// ------------------------------ 컴포넌트 ------------------------------

class _SectionHeader extends StatelessWidget {
  final String title; final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)), if (trailing != null) trailing!]));
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
            color: Colors.grey[900], // ✅ 배경: 어두운 회색
            borderRadius: BorderRadius.circular(24)
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Padding(padding: const EdgeInsets.only(top: 4.0), child: Row(children: [Icon(icon, color: iconColor, size: 28), const SizedBox(width: 12), Flexible(child: Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 18, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))])),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold)), const SizedBox(width: 6), Text(unit, style: TextStyle(color: Colors.grey[500], fontSize: 16))]), // ✅ 글씨 흰색 + 크기 UP
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.bold))),
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
    final stQual = _getAirStatus('AirQuality', airQuality.toDouble());
    final stCo2 = _getAirStatus('CO2', co2.toDouble());
    final stOdor = _getAirStatus('GAS', odor.toDouble());
    final stPm1 = _getAirStatus('PM1.0', pm1);
    final stPm25 = _getAirStatus('PM2.5', pm25);
    final stPm10 = _getAirStatus('PM10', pm10);

    return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.grey[900], // ✅ 배경: 어두운 회색
            borderRadius: BorderRadius.circular(24)
        ),
        child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _EnvBigItem(icon: Icons.thermostat, label: "온도", value: temp == 0 ? "-" : temp.toStringAsFixed(1), unit: "°C", color: Colors.redAccent)),
                  Container(width: 1, height: 60, color: Colors.grey[800]), // 구분선 색상 변경
                  Expanded(child: _EnvBigItem(icon: Icons.water_drop, label: "습도", value: humidity == 0 ? "-" : humidity.round().toString(), unit: "%", color: Colors.blueAccent)),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, thickness: 1, color: Colors.white10), // 구분선 색상 변경
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _EnvSmallItem(label: "통합대기", value: stQual.label, unit: "", statusColor: stQual.color, onTap: () => _showGuideDialog(context, "통합대기"))),
                  Expanded(child: _EnvSmallItem(label: "이산화탄소", value: "$co2", unit: "ppm", statusColor: stCo2.color, onTap: () => _showGuideDialog(context, "이산화탄소"))),
                  Expanded(child: _EnvSmallItem(label: "냄새강도", value: stOdor.label, unit: "", statusColor: stOdor.color, onTap: () => _showGuideDialog(context, "냄새(GAS)"))),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _EnvSmallItem(label: "초미세(1.0)", value: "${pm1.round()}", unit: "µg", statusColor: stPm1.color, onTap: () => _showGuideDialog(context, "초미세먼지(PM1.0)"))),
                  Expanded(child: _EnvSmallItem(label: "미세(2.5)", value: "${pm25.round()}", unit: "µg", statusColor: stPm25.color, onTap: () => _showGuideDialog(context, "미세먼지(PM2.5)"))),
                  Expanded(child: _EnvSmallItem(label: "미세(10)", value: "${pm10.round()}", unit: "µg", statusColor: stPm10.color, onTap: () => _showGuideDialog(context, "미세먼지(PM10)"))),
                ],
              )
            ]
        )
    );
  }
}

class _EnvBigItem extends StatelessWidget {
  final IconData icon; final String label; final String value; final String unit; final Color color;
  const _EnvBigItem({required this.icon, required this.label, required this.value, required this.unit, required this.color});
  @override Widget build(BuildContext context) => Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 24, color: Colors.grey[500]), const SizedBox(width: 8), Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[400], fontWeight: FontWeight.w600))]), const SizedBox(height: 6), Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(value, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white, height: 1.0)), Padding(padding: const EdgeInsets.only(bottom: 6, left: 4), child: Text(unit, style: TextStyle(fontSize: 16, color: Colors.grey[500], fontWeight: FontWeight.w600)))])]);
}

class _EnvSmallItem extends StatelessWidget {
  final String label; final String value; final String unit; final Color statusColor; final VoidCallback? onTap;
  const _EnvSmallItem({required this.label, required this.value, required this.unit, required this.statusColor, this.onTap});
  @override
  Widget build(BuildContext context) {
    String statusText = "분석중";
    if (statusColor == Colors.blueAccent) statusText = "좋음";
    else if (statusColor == Colors.green) statusText = "보통";
    else if (statusColor == Colors.amber) statusText = "나쁨";
    else if (statusColor == Colors.redAccent) statusText = "매우나쁨";

    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(children: [Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[500])), const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), if (unit.isNotEmpty) ...[const SizedBox(width: 2), Text(unit, style: TextStyle(fontSize: 12, color: Colors.grey[500]))]]), const SizedBox(height: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)))])
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final _NotificationItem item; const _NotificationCard({required this.item});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(20)), child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: item.isAlert ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1), shape: BoxShape.circle), child: Icon(item.icon, size: 24, color: item.isAlert ? Colors.redAccent : Colors.blueAccent)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 2), const SizedBox(height: 6), Text(item.time, style: TextStyle(fontSize: 14, color: Colors.grey[500]))]))]));
}

class _NotificationItem { final IconData icon; final String text; final String time; final bool isAlert; const _NotificationItem({required this.icon, required this.text, required this.time, required this.isAlert}); }

// 공기질 및 팝업 로직
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
      backgroundColor: Colors.grey[900], // ✅ 팝업 배경도 다크하게
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$title 기준", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            const Text("🟦 파랑 (좋음)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 4),
            _buildGuideText(title, 0),
            const SizedBox(height: 12),
            const Text("🟩 초록 (보통)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 4),
            _buildGuideText(title, 1),
            const SizedBox(height: 12),
            const Text("🟨 노랑 (나쁨)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
            const SizedBox(height: 4),
            _buildGuideText(title, 2),
            const SizedBox(height: 12),
            const Text("🟥 빨강 (매우나쁨)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            const SizedBox(height: 4),
            _buildGuideText(title, 3),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white, elevation: 0),
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
  return Text(text, style: TextStyle(fontSize: 16, color: Colors.grey[400]));
}