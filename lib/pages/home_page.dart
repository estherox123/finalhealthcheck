// lib/pages/home_page.dart
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// 페이지 이동
import 'package:finalhealthcheck/pages/sleep_detail_page.dart';
import 'package:finalhealthcheck/pages/heart_rate_detail_page.dart';
import 'package:finalhealthcheck/pages/steps_page.dart';

// 데이터 및 로직
import '../controllers/dashboard_controller.dart';
import '../data/health_repository.dart';
import '../widgets/permission_banner.dart';
import '../data/health_data_service.dart';
import '../widgets/top_settings_menu.dart';

// IoT
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

// ------------------------------ 홈 대시보드 (시니어 친화적 디자인) ------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 헬스 더미 데이터
  int _sleepScoreDummy = 82;
  int _sleepDeltaDummy = 1;
  int _heartRateDummy = 68;
  int _hrDeltaDummy = 0;
  int _hrvDummy = 52;
  int _hrvDeltaDummy = -1;
  int _activityMinutesDummy = 45;
  int _activityDeltaDummy = 0;

  // 환경 더미 (센서 없는 값)
  int co2 = 820;
  double pm25 = 22.0;

  static const List<_NotificationItem> _lastNoti = [
    _NotificationItem(icon: Icons.air, text: '환기 필요: 공기가 탁해요', time: '10분 전', isAlert: true),
    _NotificationItem(icon: Icons.nightlight_round, text: '취침 예약 실행됨', time: '1시간 전', isAlert: false),
    _NotificationItem(icon: Icons.directions_walk, text: '걸음 목표 달성!', time: '2시간 전', isAlert: false),
  ];

  late final DashboardController _dc;
  late final DeviceControlController _iotDc;

  final ModeService _modeSvc = DummyModeService();

  QuickMode _mode = QuickMode.daily;
  bool _modeBusy = false;

  @override
  void initState() {
    super.initState();
    // 1. Health Controller
    _dc = DashboardController(HealthRepositoryImpl());
    _dc.addListener(_onRefreshUI);
    _dc.init();

    // 2. IoT Controller
    try {
      final iotApi = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
      _iotDc = DeviceControlController(IotRepository(iotApi));
      _iotDc.addListener(_onRefreshUI);
      _iotDc.init();
    } catch (e) {
      debugPrint('IoT Init Error: $e');
    }
  }

  void _onRefreshUI() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dc.removeListener(_onRefreshUI);
    _iotDc.removeListener(_onRefreshUI);
    super.dispose();
  }

  Future<void> _setMode(QuickMode m) async {
    if (_modeBusy || _mode == m) return;
    final prev = _mode;
    setState(() {
      _mode = m;
      _modeBusy = true;
    });

    try {
      await _modeSvc.apply(m);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_modeName(m)} 모드로 변경했습니다.', style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _mode = prev);
    } finally {
      if (mounted) setState(() => _modeBusy = false);
    }
  }

  String _modeName(QuickMode m) {
    switch (m) {
      case QuickMode.sleep: return '수면';
      case QuickMode.rest: return '휴식';
      case QuickMode.daily: return '일상';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('M월 d일 EEEE', 'ko').format(now);
    final greet = _greeting(now);

    // 데이터 준비
    final snap = _dc.snapshot;
    final loading = _dc.status == DashboardStatus.loading;

    final sleepScore = snap?.sleepScore ?? _sleepScoreDummy;
    final sleepDelta = snap?.deltaVs7d['sleep'] ?? _sleepDeltaDummy;
    final heartRate = snap?.heartRateAvg ?? _heartRateDummy;
    final hrDelta = snap?.deltaVs7d['hr'] ?? _hrDeltaDummy;
    final hrv = snap?.hrvRmssd ?? _hrvDummy;
    final hrvDelta = snap?.deltaVs7d['hrv'] ?? _hrvDeltaDummy;
    final activityMinutes = _activityMinutesDummy;
    final activityDelta = _activityDeltaDummy;

    // IoT 데이터
    final iotSnap = _iotDc.snapshot;
    double temp = iotSnap.aircon.currentTemperature;
    double humidity = iotSnap.aircon.currentHumidity;
    if (temp == 0.0) temp = 24.6;
    if (humidity == 0.0) humidity = 45.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // 눈이 편한 연한 회색 배경
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F2F5),
        elevation: 0,
        // 앱바에는 간단한 타이틀만 남김
        title: const Text("건강 대시보드", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: const [TopSettingsMenu(), SizedBox(width: 8)],
        bottom: loading
            ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator(minHeight: 4))
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_dc.refresh(), _iotDc.init()]);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            if (_dc.status == DashboardStatus.noPermission)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: PermissionBanner(
                  types: kRecommendedTypes,
                  onGranted: () async => _dc.retryAfterPermission(),
                ),
              ),

            // 1. [수정] 인사말 & 날짜 (앱바에서 분리하여 크게 표시)
            const SizedBox(height: 10),
            Text(greet, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.3, color: Colors.black87)),
            const SizedBox(height: 8),
            Text(dateStr, style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w500)),
            const SizedBox(height: 30),

            // 2. 오늘의 컨디션
            _SectionHeader(title: '오늘의 컨디션'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1, // 카드를 가로로 더 길게
              children: [
                _HealthCard(
                  title: '수면 점수',
                  value: sleepScore.toString(),
                  unit: '점',
                  icon: Icons.bedtime,
                  color: _statusColorFor('sleep', sleepScore),
                  statusLabel: _getStatusLabel('sleep', sleepScore),
                  delta: sleepDelta,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepDetailPage())),
                ),
                _HealthCard(
                  title: '심박수',
                  value: heartRate.toString(),
                  unit: 'bpm',
                  icon: Icons.favorite,
                  color: _statusColorFor('hr', heartRate),
                  statusLabel: _getStatusLabel('hr', heartRate),
                  delta: hrDelta,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeartRateDetailPage())),
                ),
                _HealthCard(
                  title: '심박변이도',
                  value: hrv.toString(),
                  unit: 'ms',
                  icon: Icons.multiline_chart,
                  color: _statusColorFor('hrv', hrv),
                  statusLabel: _getStatusLabel('hrv', hrv),
                  delta: hrvDelta,
                  onTap: () {},
                ),
                _HealthCard(
                  title: '활동 시간',
                  value: activityMinutes.toString(),
                  unit: '분',
                  icon: Icons.directions_walk,
                  color: Colors.teal,
                  statusLabel: '보통', // 더미
                  delta: activityDelta,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StepsPage())),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // 3. 실내 환경 (글씨 키움)
            _SectionHeader(title: '우리 집 날씨'),
            _EnvironmentBigCard(
              temp: temp,
              humidity: humidity,
              co2: co2,
              pm25: pm25,
            ),
            const SizedBox(height: 32),

            // 4. 빠른 모드
            _SectionHeader(title: '모드 변경'),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  Expanded(child: _ModeToggleBtn(label: '수면', icon: Icons.bedtime_rounded, isSelected: _mode == QuickMode.sleep, onTap: () => _setMode(QuickMode.sleep))),
                  Expanded(child: _ModeToggleBtn(label: '휴식', icon: Icons.spa_rounded, isSelected: _mode == QuickMode.rest, onTap: () => _setMode(QuickMode.rest))),
                  Expanded(child: _ModeToggleBtn(label: '일상', icon: Icons.wb_sunny_rounded, isSelected: _mode == QuickMode.daily, onTap: () => _setMode(QuickMode.daily))),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 5. 알림 (글씨 키움)
            _SectionHeader(title: '최근 알림', trailing: TextButton(onPressed: (){}, child: const Text("더보기", style: TextStyle(fontSize: 16)))),
            ..._lastNoti.map((n) => _NotificationCard(item: n)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ------------------------------ 컴포넌트 (시니어 맞춤형) ------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 섹션 제목 크게
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// 1. 건강 카드 (원형 그래프 제거 -> 막대바 + 큰 글씨)
class _HealthCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final String statusLabel; // "좋음", "보통" 텍스트
  final int delta;
  final VoidCallback? onTap;

  const _HealthCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.statusLabel,
    required this.delta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 상단: 아이콘 + 제목
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Flexible(child: Text(title, style: TextStyle(fontSize: 15, color: Colors.grey[700], fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ),

            // 중단: 아주 큰 값
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0)),
                    const SizedBox(width: 4),
                    Text(unit, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 8),
                // 하단: 막대 바 + 상태 텍스트 (직관적)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(statusLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                    ),
                    const Spacer(),
                    _DeltaIcon(delta: delta),
                  ],
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaIcon extends StatelessWidget {
  final int delta;
  const _DeltaIcon({required this.delta});
  @override
  Widget build(BuildContext context) {
    if (delta == 0) return const SizedBox.shrink();
    final isUp = delta > 0;
    // 건강 수치는 오르는게 좋은 경우도 있고 나쁜 경우도 있지만, 여기선 빨강/파랑으로 단순 등락 표시
    // 시니어 배려: 색상보다는 화살표 모양으로 인지하도록
    return Icon(
      isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      size: 20,
      color: Colors.grey[400],
    );
  }
}

// 2. 실내 환경 카드 (글씨를 아주 크게, 2x2 배치)
class _EnvironmentBigCard extends StatelessWidget {
  final double temp;
  final double humidity;
  final int co2;
  final double pm25;

  const _EnvironmentBigCard({required this.temp, required this.humidity, required this.co2, required this.pm25});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          // 상단: 온도와 습도 (가장 중요하므로 크게)
          Row(
            children: [
              Expanded(child: _EnvBigItem(icon: Icons.thermostat, label: "온도", value: temp.toStringAsFixed(1), unit: "°C", color: Colors.redAccent)),
              Container(width: 1, height: 60, color: Colors.grey[200]),
              Expanded(child: _EnvBigItem(icon: Icons.water_drop, label: "습도", value: humidity.round().toString(), unit: "%", color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 24),
          // 하단: 공기질 (조금 작게)
          Row(
            children: [
              Expanded(child: _EnvSmallItem(label: "이산화탄소", value: "$co2", unit: "ppm", isGood: co2 < 1000)),
              Expanded(child: _EnvSmallItem(label: "미세먼지", value: "${pm25.round()}", unit: "µg", isGood: pm25 < 35)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnvBigItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _EnvBigItem({required this.icon, required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0)),
            Padding(
              padding: const EdgeInsets.only(bottom: 5, left: 4),
              child: Text(unit, style: TextStyle(fontSize: 16, color: Colors.grey[500], fontWeight: FontWeight.w600)),
            ),
          ],
        )
      ],
    );
  }
}

class _EnvSmallItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool isGood;
  const _EnvSmallItem({required this.label, required this.value, required this.unit, required this.isGood});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
            Text(unit, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(width: 6),
            // 상태 점
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isGood ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(isGood ? "좋음" : "주의", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isGood ? Colors.green : Colors.orange)),
            )
          ],
        )
      ],
    );
  }
}

// 3. 모드 버튼 (더 크고 누르기 쉽게)
class _ModeToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeToggleBtn({required this.label, required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 16), // 세로 길이 늘림
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigoAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey[400], size: 28), // 아이콘 크기 확대
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// 4. 알림 카드 (글씨 확대)
class _NotificationCard extends StatelessWidget {
  final _NotificationItem item;
  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.isAlert ? Colors.red[50] : Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 22, color: item.isAlert ? Colors.redAccent : Colors.blueAccent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87), maxLines: 2),
                const SizedBox(height: 4),
                Text(item.time, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationItem {
  final IconData icon;
  final String text;
  final String time;
  final bool isAlert;
  const _NotificationItem({required this.icon, required this.text, required this.time, required this.isAlert});
}

// 헬퍼 함수들
Color _statusColorFor(String key, num value) {
  if (key == 'sleep' && value >= 80) return Colors.indigoAccent;
  if (key == 'hr' && (value >= 60 && value <= 100)) return Colors.redAccent;
  if (key == 'hrv' && value >= 40) return Colors.green;
  return Colors.orangeAccent;
}

String _getStatusLabel(String key, num value) {
  if (key == 'sleep') return value >= 80 ? "충분함" : "부족함";
  if (key == 'hr') return (value >= 60 && value <= 100) ? "정상" : "주의";
  if (key == 'hrv') return value >= 40 ? "안정됨" : "스트레스";
  return "보통";
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 6) return '편안한 밤\n보내고 계신가요? 🌙';
  if (h < 11) return '상쾌한 아침,\n건강을 챙겨보세요 ☀️';
  if (h < 18) return '나른한 오후,\n스트레칭 어때요? 🌿';
  return '오늘 하루도\n고생 많으셨어요 ✨';
}