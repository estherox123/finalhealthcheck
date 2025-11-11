// lib/pages/home_page.dart
/// 홈페이지 (대시보드). 핵심 의료 데이터 + 실내 환경 + 빠른 모드 변환 + 최근 알림

import 'package:flutter/material.dart';
import 'package:finalhealthcheck/pages/sleep_detail_page.dart';

import '../controllers/dashboard_controller.dart';
import '../data/health_repository.dart';
import '../widgets/permission_banner.dart';
import '../data/health_data_service.dart';
import '../widgets/top_settings_menu.dart';


// ------------------------------ 홈 대시보드 ------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 더미 초기값(실데이터 로드 전까지 표시)
  int _sleepScoreDummy = 82; int _sleepDeltaDummy = 1;
  int _heartRateDummy = 68;  int _hrDeltaDummy = 0;
  int _hrvDummy = 52;        int _hrvDeltaDummy = -1;
  double _respDummy = 14.5;  int _respDeltaDummy = 0;

  // 환경 더미(추후 IoT 연동 예정)
  double temp = 24.6;     // °C
  double humidity = 45.0; // %
  int co2 = 820;          // ppm
  double pm25 = 22.0;     // µg/m³

  final List<_NotificationItem> lastNoti = const [
    _NotificationItem(icon: Icons.air, text: '환기 권장: CO₂가 곧 1000ppm에 도달'),
    _NotificationItem(icon: Icons.nightlight_round, text: '수면 모드 예약: 22:30에 자동 전환'),
    _NotificationItem(icon: Icons.health_and_safety, text: '걸음수 목표 80% 달성!'),
  ];

  late final DashboardController _dc;

  @override
  void initState() {
    super.initState();
    _dc = DashboardController(HealthRepositoryImpl());
    _dc.addListener(_onDc);
    _dc.init();
  }

  void _onDc() => setState(() {});

  @override
  void dispose() {
    _dc.removeListener(_onDc);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final now = DateTime.now();
    final dateStr = '${now.year}.${_two(now.month)}.${_two(now.day)} (${_weekdayKR(now.weekday)})';
    final greet = _greeting(now);

    // Compact 모드: 화면 폭이 좁거나 텍스트 배율이 큰 경우
    final double w = media.size.width;
    final double textScale = media.textScaler.scale(1.0);
    final bool compact = (w < 400) || (textScale > 1.2);

    // 레이아웃 파라미터
    final double hPad = compact ? 12.0 : 16.0;
    final double gap = compact ? 8.0 : 12.0;
    final double typeScale = compact ? 0.92 : 1.0;

    // 컨디션 카드: Wrap 2열
    final double gridSpacing = gap;
    final double cardWidth = (w - hPad * 2 - gridSpacing) / 2;

    // 컨트롤러 스냅샷 → 값 (없으면 더미 사용)
    final snap = _dc.snapshot;
    final loading = _dc.status == DashboardStatus.loading;

    final int? sleepScore = snap?.sleepScore ?? _sleepScoreDummy;
    final int sleepDelta = snap?.deltaVs7d['sleep'] ?? _sleepDeltaDummy;

    final int? heartRate = snap?.heartRateAvg ?? _heartRateDummy;
    final int hrDelta = snap?.deltaVs7d['hr'] ?? _hrDeltaDummy;

    final int? hrv = snap?.hrvRmssd ?? _hrvDummy;
    final int hrvDelta = snap?.deltaVs7d['hrv'] ?? _hrvDeltaDummy;

    final double? respiration = snap?.respirationNight ?? _respDummy;
    final int respDelta = snap?.deltaVs7d['resp'] ?? _respDeltaDummy;

    return Scaffold(
      appBar: AppBar(
          title: const Text('오늘의 건강 대시보드'),
          actions: const [TopSettingsMenu(), SizedBox(width: 4),]),
      body: RefreshIndicator(
        onRefresh: () => _dc.refresh(),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
            children: [
              if (_dc.status == DashboardStatus.noPermission)
                PermissionBanner(
                  // 권장 타입 세트 (health_data_service.dart 에 정의됨)
                  types: kRecommendedTypes,
                  // 설정에서 허용하고 돌아오면 자동 콜백
                  onGranted: () async => _dc.retryAfterPermission(),
                ),

              // 1) 인사 / 날짜
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greet,
                            maxLines: 2,
                            style: _scale(
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                letterSpacing: -0.1,
                              ),
                              typeScale,
                            )),
                        const SizedBox(height: 4),
                        Text(dateStr,
                            maxLines: 1,
                            style: _scale(
                              Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                              typeScale,
                            )),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    radius: compact ? 18 : 22,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    child: Icon(Icons.face_6_outlined, color: Theme.of(context).colorScheme.primary),
                  )
                ],
              ),
              const SizedBox(height: 12),

              // 2) 오늘의 컨디션 (Wrap 2열)
              Text('오늘의 컨디션',
                  style: _scale(
                    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    typeScale,
                  )),
              const SizedBox(height: 8),
              Wrap(
                spacing: gridSpacing,
                runSpacing: gridSpacing,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _ConditionCard(
                      title: '수면 점수',
                      valueText: (sleepScore == null) ? '-' : '$sleepScore',
                      unit: (sleepScore == null) ? '' : '/100',
                      color: _statusColorFor('sleep', (sleepScore ?? 0)),
                      delta: sleepDelta,
                      caption: '7일 평균 대비',
                      icon: Icons.bedtime_outlined,
                      typeScale: typeScale,
                      compact: compact,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepDetailPage())),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ConditionCard(
                      title: '심박수',
                      valueText: (heartRate == null) ? '-' : '$heartRate',
                      unit: (heartRate == null) ? '' : ' bpm',
                      color: _statusColorFor('hr', (heartRate ?? 0)),
                      delta: hrDelta,
                      caption: '7일 평균 대비',
                      icon: Icons.favorite_outline,
                      typeScale: typeScale,
                      compact: compact,
                      onTap: loading ? null : () {},
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ConditionCard(
                      title: '심박변이도',
                      valueText: (hrv == null) ? '-' : '$hrv',
                      unit: (hrv == null) ? '' : ' ms',
                      color: _statusColorFor('hrv', (hrv ?? 0)),
                      delta: hrvDelta,
                      caption: '7일 평균 대비',
                      icon: Icons.multiline_chart,
                      typeScale: typeScale,
                      compact: compact,
                      onTap: loading ? null : () {},
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ConditionCard(
                      title: '호흡수',
                      valueText: (respiration == null) ? '-' : respiration!.toStringAsFixed(1),
                      unit: (respiration == null) ? '' : ' rpm',
                      color: _statusColorFor('resp', (respiration ?? 0)),
                      delta: respDelta,
                      caption: '야간 평균',
                      icon: Icons.air_outlined,
                      typeScale: typeScale,
                      compact: compact,
                      onTap: loading ? null : () {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3) 실내 환경 (더미 값)
              Text('실내 환경',
                  style: _scale(
                    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    typeScale,
                  )),
              const SizedBox(height: 8),

              if (!compact) ...[
                Row(
                  children: [
                    Expanded(
                      child: _EnvTile.horizontal(
                        label: '온도',
                        value: '${temp.toStringAsFixed(1)}°C',
                        color: _colorForGrade(_gradeTemp(temp)),
                        icon: Icons.thermostat_outlined,
                        typeScale: typeScale,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _EnvTile.horizontal(
                        label: '습도',
                        value: '${humidity.toStringAsFixed(0)}%',
                        color: _colorForGrade(_gradeHum(humidity)),
                        icon: Icons.water_drop_outlined,
                        typeScale: typeScale,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gap),
                Row(
                  children: [
                    Expanded(
                      child: _EnvTile.horizontal(
                        label: 'CO₂',
                        value: '${co2}ppm',
                        color: _colorForGrade(_gradeCO2(co2)),
                        icon: Icons.co2_outlined,
                        typeScale: typeScale,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _EnvTile.horizontal(
                        label: 'PM2.5',
                        value: pm25.toStringAsFixed(1),
                        color: _colorForGrade(_gradePM25(pm25)),
                        icon: Icons.blur_on_outlined,
                        typeScale: typeScale,
                        trailing: (pm25 > 35.0)
                            ? TextButton(
                          onPressed: () {},
                          child: const Text('조치하기', style: TextStyle(fontWeight: FontWeight.w600)),
                        )
                            : null,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                _EnvTile.vertical(
                  label: '온도',
                  value: '${temp.toStringAsFixed(1)}°C',
                  color: _colorForGrade(_gradeTemp(temp)),
                  icon: Icons.thermostat_outlined,
                  typeScale: typeScale,
                ),
                SizedBox(height: gap),
                _EnvTile.vertical(
                  label: '습도',
                  value: '${humidity.toStringAsFixed(0)}%',
                  color: _colorForGrade(_gradeHum(humidity)),
                  icon: Icons.water_drop_outlined,
                  typeScale: typeScale,
                ),
                SizedBox(height: gap),
                _EnvTile.vertical(
                  label: 'CO₂',
                  value: '${co2}ppm',
                  color: _colorForGrade(_gradeCO2(co2)),
                  icon: Icons.co2_outlined,
                  typeScale: typeScale,
                ),
                SizedBox(height: gap),
                _EnvTile.vertical(
                  label: 'PM2.5',
                  value: pm25.toStringAsFixed(1),
                  color: _colorForGrade(_gradePM25(pm25)),
                  icon: Icons.blur_on_outlined,
                  typeScale: typeScale,
                  bottom: (pm25 > 35.0)
                      ? Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: const Text('조치하기', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  )
                      : null,
                ),
              ],

              const SizedBox(height: 16),

              // 4) 빠른 모드 토글 (더미 액션)
              Text('빠른 모드',
                  style: _scale(
                    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    typeScale,
                  )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ModeButton(
                      label: '수면',
                      icon: Icons.bedtime,
                      onPressed: () => _toast('수면 모드로 전환합니다…'),
                      typeScale: typeScale,
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: _ModeButton(
                      label: '휴식',
                      icon: Icons.spa_outlined,
                      onPressed: () => _toast('휴식 모드로 전환합니다…'),
                      typeScale: typeScale,
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: _ModeButton(
                      label: '일상',
                      icon: Icons.flash_on_outlined,
                      onPressed: () => _toast('일상 모드로 전환합니다…'),
                      typeScale: typeScale,
                      compact: compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 5) 최근 알림 3개 (더미)
              Text('최근 알림',
                  style: _scale(
                    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    typeScale,
                  )),
              const SizedBox(height: 8),
              ...lastNoti.take(3).map((n) => _NotiTile(item: n, typeScale: typeScale)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('더 보기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------- 유틸 ---------------------------

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  TextStyle? _scale(TextStyle? s, double f) =>
      s?.copyWith(fontSize: (s.fontSize ?? 14) * f);

  Color _statusColorFor(String key, num value) {
    switch (key) {
      case 'sleep':
        if (value >= 80) return Colors.green;
        if (value >= 60) return Colors.orange;
        return Colors.red;
      case 'hr':
        if (value >= 50 && value <= 90) return Colors.green;
        if ((value > 90 && value <= 100) || (value >= 45 && value < 50)) return Colors.orange;
        return Colors.red;
      case 'hrv':
        if (value >= 50) return Colors.green;
        if (value >= 30) return Colors.orange;
        return Colors.red;
      case 'resp':
        if (value >= 12 && value <= 18) return Colors.green;
        if ((value >= 10 && value < 12) || (value > 18 && value <= 20)) return Colors.orange;
        return Colors.red;
    }
    return Colors.grey;
  }

  _Grade _gradeTemp(double c) {
    if (c >= 20 && c <= 24) return _Grade.good;
    if ((c > 24 && c <= 27) || (c >= 18 && c < 20)) return _Grade.warn;
    return _Grade.bad;
  }
  _Grade _gradeHum(double h) {
    if (h >= 40 && h <= 60) return _Grade.good;
    if ((h >= 30 && h < 40) || (h > 60 && h <= 70)) return _Grade.warn;
    return _Grade.bad;
  }
  _Grade _gradeCO2(int x) {
    if (x < 1000) return _Grade.good;
    if (x <= 1500) return _Grade.warn;
    return _Grade.bad;
  }
  _Grade _gradePM25(double x) {
    if (x < 15) return _Grade.good;
    if (x <= 35) return _Grade.warn;
    return _Grade.bad;
  }
  Color _colorForGrade(_Grade g) =>
      g == _Grade.good ? Colors.green : (g == _Grade.warn ? Colors.orange : Colors.red);

  String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 6) return '늦은 밤이에요. 푹 쉬어요~';
    if (h < 12) return '좋은 아침이에요!';
    if (h < 18) return '좋은 오후예요!';
    return '좋은 저녁이에요!';
  }

  String _weekdayKR(int wd) {
    const m = {1:'월',2:'화',3:'수',4:'목',5:'금',6:'토',7:'일'};
    return m[wd] ?? '';
  }
  String _two(int x) => x.toString().padLeft(2, '0');
}

// ------------------------------ 위젯들 --------------------------------------

class _PermissionBanner extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionBanner({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_open_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Health Connect 권한이 필요합니다. 설정에서 허용해주세요.'),
          ),
          TextButton(onPressed: onRequest, child: const Text('권한 요청')),
        ],
      ),
    );
  }
}

class _ConditionCard extends StatelessWidget {
  final String title;
  final String valueText;
  final String unit;
  final int delta; // +1 / 0 / -1
  final Color color;
  final String caption;
  final IconData icon;
  final VoidCallback? onTap;
  final double typeScale;
  final bool compact;

  const _ConditionCard({
    required this.title,
    required this.valueText,
    required this.unit,
    required this.delta,
    required this.color,
    required this.caption,
    required this.icon,
    required this.onTap,
    required this.typeScale,
    required this.compact,
  });

  TextStyle? _s(TextStyle? s, double f) =>
      s?.copyWith(fontSize: (s.fontSize ?? 14) * f);

  @override
  Widget build(BuildContext context) {
    final bg = color.withOpacity(0.12);
    final arrow = delta > 0 ? Icons.arrow_upward
        : delta < 0 ? Icons.arrow_downward
        : Icons.horizontal_rule;
    final arrowColor = delta > 0 ? Colors.green : (delta < 0 ? Colors.red : Colors.grey[600]);

    return Semantics(
      label: '$title, 현재값 $valueText$unit, 변동 ${delta > 0 ? "상승" : delta < 0 ? "하락" : "변화 없음"}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: compact ? 20 : 24),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                style: _s(Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), typeScale),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              valueText,
                              maxLines: 1,
                              style: _s(Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800), typeScale),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: Text(
                                unit,
                                maxLines: 1,
                                style: _s(Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[700]), typeScale),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 22,
                    child: Icon(arrow, size: 18, color: arrowColor),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                maxLines: 2,
                style: _s(Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]), typeScale),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final double typeScale;
  final Widget? trailing; // 가로형 전용
  final Widget? bottom;   // 세로형 전용

  const _EnvTile.horizontal({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.typeScale,
    this.trailing,
  }) : bottom = null;

  const _EnvTile.vertical({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.typeScale,
    this.bottom,
  }) : trailing = null;

  TextStyle? _s(TextStyle? s, double f) =>
      s?.copyWith(fontSize: (s.fontSize ?? 14) * f);

  @override
  Widget build(BuildContext context) {
    final isVertical = bottom != null;

    if (isVertical) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withOpacity(0.18),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  style: _s(Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), 1.0),
                ),
              )
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: _s(Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800), 1.0),
              ),
            ),
            if (bottom != null) ...[
              const SizedBox(height: 6),
              bottom!,
            ],
          ],
        ),
      );
    }

    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withOpacity(0.18),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  style: _s(Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), typeScale),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: _s(Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800), typeScale),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 0, maxWidth: 120),
              child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double typeScale;
  final bool compact;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.typeScale,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: compact ? 54 : 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.withOpacity(0.10),
          foregroundColor: c,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(fontSize: (16 * typeScale), fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: compact ? 18 : 20),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationItem {
  final IconData icon;
  final String text;
  const _NotificationItem({required this.icon, required this.text});
}

class _NotiTile extends StatelessWidget {
  final _NotificationItem item;
  final double typeScale;
  const _NotiTile({required this.item, required this.typeScale});

  TextStyle? _s(TextStyle? s, double f) =>
      s?.copyWith(fontSize: (s.fontSize ?? 14) * f);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        child: Icon(item.icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(
        item.text,
        maxLines: 3,
        style: _s(const TextStyle(fontWeight: FontWeight.w600), typeScale),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    );
  }
}

enum _Grade { good, warn, bad }

// ------------------------------ 헬퍼 ------------------------------

TextStyle? _scale(TextStyle? s, double f) =>
    s?.copyWith(fontSize: (s.fontSize ?? 14) * f);

Color _statusColorFor(String key, num value) {
  switch (key) {
    case 'sleep':
      if (value >= 80) return Colors.green;
      if (value >= 60) return Colors.orange;
      return Colors.red;
    case 'hr':
      if (value >= 50 && value <= 90) return Colors.green;
      if ((value > 90 && value <= 100) || (value >= 45 && value < 50)) return Colors.orange;
      return Colors.red;
    case 'hrv':
      if (value >= 50) return Colors.green;
      if (value >= 30) return Colors.orange;
      return Colors.red;
    case 'resp':
      if (value >= 12 && value <= 18) return Colors.green;
      if ((value >= 10 && value < 12) || (value > 18 && value <= 20)) return Colors.orange;
      return Colors.red;
  }
  return Colors.grey;
}

_Grade _gradeTemp(double c) {
  if (c >= 20 && c <= 24) return _Grade.good;
  if ((c > 24 && c <= 27) || (c >= 18 && c < 20)) return _Grade.warn;
  return _Grade.bad;
}
_Grade _gradeHum(double h) {
  if (h >= 40 && h <= 60) return _Grade.good;
  if ((h >= 30 && h < 40) || (h > 60 && h <= 70)) return _Grade.warn;
  return _Grade.bad;
}
_Grade _gradeCO2(int x) {
  if (x < 1000) return _Grade.good;
  if (x <= 1500) return _Grade.warn;
  return _Grade.bad;
}
_Grade _gradePM25(double x) {
  if (x < 15) return _Grade.good;
  if (x <= 35) return _Grade.warn;
  return _Grade.bad;
}
Color _colorForGrade(_Grade g) =>
    g == _Grade.good ? Colors.green : (g == _Grade.warn ? Colors.orange : Colors.red);

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 6) return '늦은 밤이에요. 푹 쉬어요~';
  if (h < 12) return '좋은 아침이에요!';
  if (h < 18) return '좋은 오후예요!';
  return '좋은 저녁이에요!';
}

String _weekdayKR(int wd) {
  const m = {1:'월',2:'화',3:'수',4:'목',5:'금',6:'토',7:'일'};
  return m[wd] ?? '';
}
String _two(int x) => x.toString().padLeft(2, '0');
