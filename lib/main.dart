import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

import 'health_controller.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Wellness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  bool _completedOnboarding = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _completedOnboarding
          ? const MainShell(key: ValueKey('main-shell'))
          : OnboardingFlow(
              key: const ValueKey('onboarding-flow'),
              onComplete: () => setState(() => _completedOnboarding = true),
            ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                Onboarding                                  */
/* -------------------------------------------------------------------------- */
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _slidesController = PageController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  int _slidesIndex = 0;
  int _currentStep = 0;

  final List<_ChecklistEntry> _checklist = [
    _ChecklistEntry(
      title: '인터넷 연결 확인',
      detail: '와이파이 신호가 약해요. 라우터와 가까이 이동해 주세요.',
      icon: Icons.wifi_tethering,
    ),
    _ChecklistEntry(
      title: '집안 기기 연결',
      detail: '연결 필요. 아래 버튼을 눌러 기기를 등록하세요.',
      icon: Icons.devices_other,
      actionLabel: '연결하기',
    ),
    _ChecklistEntry(
      title: '필수 센서 확인',
      detail: '온도 · 습도 · CO₂ · 수면 센서 상태를 점검합니다.',
      icon: Icons.sensors,
    ),
    _ChecklistEntry(
      title: '건강 데이터 연동',
      detail: '심박 · 수면 데이터를 읽어오기 위해 권한이 필요합니다.',
      icon: Icons.favorite_outline,
    ),
  ];

  final List<_PermissionToggle> _healthDataScope = const [
    _PermissionToggle(
      title: '걸음수',
      description: '지난 7일 추세와 오늘의 합계를 확인합니다.',
      availableNow: true,
    ),
    _PermissionToggle(
      title: '수면 패턴',
      description: '수면 세션과 단계 요약을 불러옵니다.',
      availableNow: true,
    ),
    _PermissionToggle(title: '심박수', description: '실시간 심박과 평균 심박'),
    _PermissionToggle(title: '심박변이도', description: 'RMSSD, SDNN 정보'),
    _PermissionToggle(title: '호흡수', description: '야간 평균 호흡수'),
    _PermissionToggle(title: '체중', description: '기초 체중 추세'),
  ];

  static const List<HealthDataType> _healthPermissionTypes = [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_IN_BED,
  ];

  bool _healthPermissionChecking = false;
  bool? _healthPermissionGranted;
  String? _healthPermissionError;
  bool _healthStatusChecked = false;

  final List<_ConsentItem> _consentItems = [
    _ConsentItem('수면 요약'),
    _ConsentItem('심박 · 심박변이도'),
    _ConsentItem('호흡수'),
    _ConsentItem('혈압 · 체중'),
  ];

  final List<String> _hospitals = const ['우리동네 병원', '서울 홈케어 병원', '병원 연동 안 함'];
  final List<String> _frequencies = const ['주간', '월간'];
  final List<String> _recentLogs = const [];

  bool _notificationsAllowed = true;
  bool _bluetoothPaired = false;
  bool _localNetworkAllowed = false;
  bool _consentEnabled = false;
  String _selectedHospital = '우리동네 병원';
  String _selectedFrequency = '주간';

  @override
  void dispose() {
    _slidesController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isLastStep => _currentStep == _totalSteps - 1;
  int get _totalSteps => 5;

  bool get _canProceed {
    switch (_currentStep) {
      case 1:
        return _checklist.every((c) => c.checked);
      case 2:
        return _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;
      default:
        return true;
    }
  }

  void _goNext() {
    if (_isLastStep) {
      widget.onComplete();
    } else {
      setState(() => _currentStep++);
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _updateHealthPermission({bool request = false}) async {
    if (_healthPermissionChecking) return;

    setState(() {
      _healthPermissionChecking = true;
      if (request) {
        _healthPermissionError = null;
      }
    });

    bool granted = false;
    String? error;

    try {
      await HealthController.I.ensureConfigured();
      final available = await HealthController.I.health.isHealthConnectAvailable();
      if (!available) {
        error = 'Health Connect 앱을 설치하거나 업데이트한 뒤 다시 시도해 주세요.';
      } else {
        final has = request
            ? await HealthController.I.requestPermsFor(_healthPermissionTypes)
            : await HealthController.I.hasPermsFor(_healthPermissionTypes);
        granted = has;
        if (!has) {
          error = request
              ? '권한이 허용되지 않았어요. Health Connect 앱에서 다시 시도해 주세요.'
              : '필요한 권한이 아직 허용되지 않았어요.';
        }
      }
    } catch (e) {
      error = '권한 확인 중 오류: $e';
    }

    if (!mounted) return;
    setState(() {
      _healthPermissionGranted = granted;
      _healthPermissionError = granted ? null : error;
      _healthPermissionChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('시작 안내'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _totalSteps,
                  (index) => Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _currentStep
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildStep(context),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_currentStep > 0)
                    OutlinedButton.icon(
                      onPressed: _goBack,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('이전'),
                    )
                  else
                    TextButton(
                      onPressed: widget.onComplete,
                      child: const Text('건너뛰기'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _canProceed ? _goNext : null,
                    icon: Icon(_isLastStep ? Icons.check : Icons.arrow_forward),
                    label: Text(_isLastStep ? '완료' : '다음'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_currentStep) {
      case 0:
        return _buildSlides(context);
      case 1:
        return _buildChecklist(context);
      case 2:
        return _buildAccountStep(context);
      case 3:
        return _buildPermissionWizard(context);
      case 4:
        return _buildConsentStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSlides(BuildContext context) {
    final slides = [
      const _OnboardingSlide(
        icon: Icons.favorite_outline,
        title: '건강을 한눈에',
        description: '수면, 심박, 호흡 상태를 10초 안에 확인할 수 있어요.',
      ),
      const _OnboardingSlide(
        icon: Icons.light_mode_outlined,
        title: '집안 환경 자동화',
        description: '조명 · 온도 · 환기를 상황에 맞게 자동으로 조절합니다.',
      ),
      const _OnboardingSlide(
        icon: Icons.local_hospital_outlined,
        title: '병원 리포트 공유',
        description: '동의하면 주간 요약을 주치의와 공유할 수 있어요.',
      ),
      const _OnboardingSlide(
        icon: Icons.privacy_tip_outlined,
        title: '개인정보 보호',
        description: '권한은 언제든 설정에서 변경할 수 있도록 안내해 드립니다.',
      ),
    ];

    return Column(
      key: const ValueKey('slides'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('캐빈 앱 소개', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Expanded(
          child: PageView.builder(
            controller: _slidesController,
            itemCount: slides.length,
            onPageChanged: (index) => setState(() => _slidesIndex = index),
            itemBuilder: (context, index) => _SlideCard(slide: slides[index]),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: index == _slidesIndex ? 32 : 10,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: index == _slidesIndex
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklist(BuildContext context) {
    return Column(
      key: const ValueKey('checklist'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('시작 준비 확인', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('필수 연결을 모두 점검하면 다음 단계로 이동할 수 있습니다.'),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: _checklist.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = _checklist[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: item.checked,
                        onChanged: (value) => setState(() => item.checked = value ?? false),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(item.detail),
                        secondary: Icon(item.icon),
                      ),
                      if (item.actionLabel != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${item.actionLabel!} 기능은 추후 구현 예정입니다.')),
                            ),
                            child: Text(item.actionLabel!),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAccountStep(BuildContext context) {
    return ListView(
      key: const ValueKey('account'),
      children: [
        Text('로그인 / 계정 생성', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('병원 리포트와 IoT 제어 기능을 사용하려면 계정을 생성하세요.'),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '이메일'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: '비밀번호'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        const Text('계정은 건강 데이터와 IoT 장치를 안전하게 연결하는 데 사용됩니다.'),
      ],
    );
  }

  Widget _buildPermissionWizard(BuildContext context) {
    if (!_healthStatusChecked) {
      _healthStatusChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateHealthPermission();
        }
      });
    }

    final theme = Theme.of(context);
    final granted = _healthPermissionGranted == true;
    final iconColor = granted ? theme.colorScheme.primary : theme.colorScheme.error;
    final iconData = granted ? Icons.check_circle_outline : Icons.health_and_safety_outlined;

    return ListView(
      key: const ValueKey('permissions'),
      children: [
        Text('권한 요청 마법사', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('필수 권한만 선택적으로 허용할 수 있습니다. 언제든 설정에서 변경 가능합니다.'),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('알림 허용'),
          subtitle: const Text('위급 경보와 환경 변화 알림을 받을 수 있어요.'),
          value: _notificationsAllowed,
          onChanged: (value) => setState(() => _notificationsAllowed = value),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(iconData, color: iconColor),
            title: const Text('Health Connect 권한'),
            subtitle: Text(
              granted
                  ? '걸음 · 수면 데이터를 읽어올 수 있도록 권한이 허용되었습니다.'
                  : (_healthPermissionError ?? 'Health Connect에서 걸음 · 수면 데이터를 읽어올 수 있도록 허용해 주세요.'),
            ),
            trailing: _healthPermissionChecking
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed:
                        _healthPermissionChecking ? null : () => _updateHealthPermission(request: true),
                    child: Text(granted ? '다시 요청' : '권한 요청'),
                  ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _healthPermissionChecking ? null : () => _updateHealthPermission(),
            icon: const Icon(Icons.refresh),
            label: const Text('상태 새로고침'),
          ),
        ),
        const Divider(height: 32),
        const Text('건강 데이터 범위', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._healthDataScope.map(
          (item) {
            final icon = item.availableNow
                ? (granted ? Icons.check_circle : Icons.lock_outline)
                : Icons.hourglass_bottom;
            final color = item.availableNow
                ? (granted ? theme.colorScheme.primary : theme.colorScheme.outline)
                : theme.colorScheme.outline;
            final status = item.availableNow
                ? (granted
                    ? 'Health Connect에서 해당 데이터를 읽어올 수 있습니다.'
                    : '권한을 허용하면 해당 데이터를 읽어올 수 있습니다.')
                : '기능 준비 중입니다. 추후 업데이트에서 지원될 예정입니다.';

            return ListTile(
              leading: Icon(icon, color: color),
              title: Text(item.title),
              subtitle: Text('${item.description}\n$status'),
              isThreeLine: true,
            );
          },
        ),
        const Divider(height: 32),
        SwitchListTile(
          title: const Text('블루투스 기기 페어링'),
          subtitle: const Text('웨어러블과 홈 IoT 기기를 자동으로 검색합니다. (연동 준비 중)'),
          value: _bluetoothPaired,
          onChanged: (value) => setState(() => _bluetoothPaired = value),
        ),
        SwitchListTile(
          title: const Text('로컬 네트워크 접근'),
          subtitle: const Text('Home Assistant를 검색하고 기기 상태를 동기화합니다. (연동 준비 중)'),
          value: _localNetworkAllowed,
          onChanged: (value) => setState(() => _localNetworkAllowed = value),
        ),
        const SizedBox(height: 8),
        Card(
          color: theme.colorScheme.surfaceVariant,
          child: const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('권한은 언제든 설정 > 권한 & 데이터에서 수정할 수 있어요.'),
          ),
        ),
      ],
    );
  }

  Widget _buildConsentStep(BuildContext context) {
    return ListView(
      key: const ValueKey('consent'),
      children: [
        Text('병원 데이터 전송 동의', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('동의하면 설정된 주기에 맞춰 건강 요약을 병원에 전송합니다.'),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('병원 전송 동의'),
          subtitle: Text(_consentEnabled ? '요약 정보가 정해진 주기로 전송됩니다.' : '동의하지 않으면 병원 전송이 중단됩니다.'),
          value: _consentEnabled,
          onChanged: (value) => setState(() => _consentEnabled = value),
        ),
        ListTile(
          title: const Text('전송 대상 병원'),
          subtitle: Text(_selectedHospital),
          trailing: DropdownButton<String>(
            value: _selectedHospital,
            items: _hospitals.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
            onChanged: (value) => setState(() => _selectedHospital = value ?? _selectedHospital),
          ),
        ),
        ListTile(
          title: const Text('전송 주기'),
          subtitle: Text(_selectedFrequency),
          trailing: DropdownButton<String>(
            value: _selectedFrequency,
            items: _frequencies.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (value) => setState(() => _selectedFrequency = value ?? _selectedFrequency),
          ),
        ),
        const Divider(height: 32),
        const Text('전송 항목 선택'),
        const SizedBox(height: 8),
        ..._consentItems.map(
          (item) => CheckboxListTile(
            title: Text(item.label),
            value: item.enabled,
            onChanged: (value) => setState(() => item.enabled = value ?? false),
          ),
        ),
        const Divider(height: 32),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: const Text('전송 이력'),
                trailing: IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PDF/CSV 내보내기는 추후 구현 예정입니다.')),
                  ),
                ),
              ),
              if (_recentLogs.isEmpty)
                const ListTile(
                  leading: Icon(Icons.history),
                  title: Text('전송 이력이 아직 없습니다.'),
                  subtitle: Text('건강 데이터를 연동하면 최근 전송 기록이 표시됩니다.'),
                )
              else
                ..._recentLogs.map(
                  (log) => ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(log),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('개인정보 처리방침 화면은 추후 연결됩니다.')),
          ),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('개인정보 고지 확인'),
        ),
      ],
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(slide.icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text(slide.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(slide.description, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _ChecklistEntry {
  _ChecklistEntry({
    required this.title,
    required this.detail,
    required this.icon,
    this.actionLabel,
    this.checked = false,
  });

  final String title;
  final String detail;
  final IconData icon;
  final String? actionLabel;
  bool checked;
}

class _PermissionToggle {
  const _PermissionToggle({required this.title, required this.description, this.availableNow = false});

  final String title;
  final String description;
  final bool availableNow;
}

class _ConsentItem {
  _ConsentItem(this.label, {this.enabled = true});

  final String label;
  bool enabled;
}

/* -------------------------------------------------------------------------- */
/*                                 Main Shell                                 */
/* -------------------------------------------------------------------------- */
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['홈', '건강', '집안 제어', '응급 연락'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          HomeDashboardPage(),
          HealthHubPage(),
          HomeControlPage(),
          EmergencyContactsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: '건강'),
          NavigationDestination(icon: Icon(Icons.devices_other_outlined), selectedIcon: Icon(Icons.devices_other), label: '제어'),
          NavigationDestination(icon: Icon(Icons.sos_outlined), selectedIcon: Icon(Icons.sos), label: '응급'),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                 Home Page                                  */
/* -------------------------------------------------------------------------- */
class HomeDashboardPage extends StatelessWidget {
  const HomeDashboardPage({super.key});

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '편안한 밤, 캐빈님';
    if (hour < 12) return '좋은 아침, 캐빈님';
    if (hour < 18) return '활기찬 오후예요, 캐빈님';
    return '잔잔한 저녁이네요, 캐빈님';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat.yMMMMEEEEd().format(DateTime.now());
    final theme = Theme.of(context);

    const conditionMetrics = [
      _ConditionMetric(
        icon: Icons.nightlight_round,
        title: '수면 점수',
        value: '데이터 없음',
        trend: 'Health Connect 권한을 허용해 주세요.',
        level: _StatusLevel.warning,
        caption: '수면 데이터 연동 필요',
      ),
      _ConditionMetric(
        icon: Icons.favorite_outline,
        title: '평균 심박',
        value: '데이터 없음',
        trend: '웨어러블 연동 후 확인할 수 있어요.',
        level: _StatusLevel.warning,
        caption: '심박 데이터 연결 필요',
      ),
      _ConditionMetric(
        icon: Icons.bolt_outlined,
        title: '심박변이도',
        value: '데이터 없음',
        trend: 'Health Connect에서 허용되면 추세를 분석합니다.',
        level: _StatusLevel.warning,
        caption: '심박변이도 연동 필요',
      ),
      _ConditionMetric(
        icon: Icons.air_outlined,
        title: '야간 호흡수',
        value: '데이터 없음',
        trend: '야간 호흡 데이터를 아직 받아오지 못했습니다.',
        level: _StatusLevel.warning,
        caption: '데이터 연동 필요',
      ),
    ];

    const environmentMetrics = [
      _EnvironmentMetric(title: '온도', value: '데이터 없음', hint: 'Home Assistant 센서를 연결해 주세요.', level: _StatusLevel.warning),
      _EnvironmentMetric(title: '습도', value: '데이터 없음', hint: '센서 연동 시 실시간으로 표시됩니다.', level: _StatusLevel.warning),
      _EnvironmentMetric(title: 'CO₂', value: '데이터 없음', hint: '공기질 센서 연결이 필요합니다.', level: _StatusLevel.warning),
      _EnvironmentMetric(title: 'PM2.5', value: '데이터 없음', hint: '센서 연동 후 공기질을 안내해 드릴게요.', level: _StatusLevel.warning),
    ];

    const recentAlerts = [
      '걸음 데이터가 아직 동기화되지 않았어요. Health Connect 권한을 확인해 주세요.',
      '실내 센서가 연결되지 않았습니다. 네트워크 상태를 점검해 주세요.',
      '병원 리포트 전송을 시작하려면 동의 절차를 완료해 주세요.',
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_greetingText(), style: theme.textTheme.headlineSmall),
          Text(today, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('오늘의 컨디션', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: conditionMetrics
                        .map((metric) => _ConditionMetricCard(data: metric))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('의료적 판단은 의료진과 상의하세요.', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('실내 환경', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: environmentMetrics
                        .map((metric) => _EnvironmentMetricCard(data: metric))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('빠른 모드 토글', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showSnack(context, '수면 모드로 전환합니다.'),
                          icon: const Icon(Icons.bedtime_outlined),
                          label: const Text('수면'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showSnack(context, '휴식 모드로 전환합니다.'),
                          icon: const Icon(Icons.self_improvement_outlined),
                          label: const Text('휴식'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showSnack(context, '일상 모드로 전환합니다.'),
                          icon: const Icon(Icons.wb_sunny_outlined),
                          label: const Text('일상'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('최근 알림', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final alert in recentAlerts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(alert),
                      trailing: TextButton(
                        onPressed: () => _showSnack(context, '알림에 대한 응답 처리 예정'),
                        child: const Text('확인'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConditionMetricCard extends StatelessWidget {
  const _ConditionMetricCard({required this.data});

  final _ConditionMetric data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _statusChipStyle(data.level, scheme);

    return SizedBox(
      width: 160,
      child: Card(
        color: scheme.surfaceVariant.withOpacity(0.6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(data.icon, color: scheme.primary),
              const SizedBox(height: 8),
              Text(data.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                data.value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(data.trend, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: style.background, borderRadius: BorderRadius.circular(12)),
                child: Text(style.label, style: TextStyle(color: style.foreground, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (data.caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(data.caption!, style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvironmentMetricCard extends StatelessWidget {
  const _EnvironmentMetricCard({required this.data});

  final _EnvironmentMetric data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _statusChipStyle(data.level, scheme);

    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                data.value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: style.background, borderRadius: BorderRadius.circular(12)),
                child: Text(style.label, style: TextStyle(color: style.foreground, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              Text(data.hint, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StatusLevel { good, warning, danger }

class _StatusChipStyle {
  const _StatusChipStyle({required this.background, required this.foreground, required this.label});

  final Color background;
  final Color foreground;
  final String label;
}

_StatusChipStyle _statusChipStyle(_StatusLevel level, ColorScheme scheme) {
  switch (level) {
    case _StatusLevel.good:
      return _StatusChipStyle(
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        label: '괜찮음',
      );
    case _StatusLevel.warning:
      return _StatusChipStyle(
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        label: '주의',
      );
    case _StatusLevel.danger:
      return _StatusChipStyle(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        label: '도움 필요',
      );
  }
}

class _ConditionMetric {
  const _ConditionMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.trend,
    required this.level,
    this.caption,
  });

  final IconData icon;
  final String title;
  final String value;
  final String trend;
  final _StatusLevel level;
  final String? caption;
}

class _EnvironmentMetric {
  const _EnvironmentMetric({
    required this.title,
    required this.value,
    required this.hint,
    required this.level,
  });

  final String title;
  final String value;
  final String hint;
  final _StatusLevel level;
}

/* -------------------------------------------------------------------------- */
/*                                 Health Hub                                 */
/* -------------------------------------------------------------------------- */
class HealthHubPage extends StatefulWidget {
  const HealthHubPage({super.key});

  @override
  State<HealthHubPage> createState() => _HealthHubPageState();
}

class _HealthHubPageState extends State<HealthHubPage> {
  Set<_HealthRange> _selectedRange = const {_HealthRange.today};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const summaryTiles = [
      _HealthSummaryTile(
        icon: Icons.local_hotel_outlined,
        title: '총수면',
        value: '데이터 없음',
        level: _StatusLevel.warning,
        caption: '수면 데이터 연동 후 요약을 제공합니다.',
      ),
      _HealthSummaryTile(
        icon: Icons.directions_walk_outlined,
        title: '활동량',
        value: '데이터 없음',
        level: _StatusLevel.warning,
        caption: '걸음 데이터를 불러오면 목표 진행률을 보여드릴게요.',
      ),
      _HealthSummaryTile(
        icon: Icons.favorite_outline,
        title: '평균 심박',
        value: '데이터 없음',
        level: _StatusLevel.warning,
        caption: '웨어러블 연동이 필요합니다.',
      ),
      _HealthSummaryTile(
        icon: Icons.monitor_heart_outlined,
        title: '심박변이도',
        value: '데이터 없음',
        level: _StatusLevel.warning,
        caption: '권한 허용 시 추세를 분석합니다.',
      ),
      _HealthSummaryTile(
        icon: Icons.bloodtype_outlined,
        title: '혈압',
        value: '데이터 없음',
        level: _StatusLevel.warning,
        caption: '측정값이 연동되면 표시됩니다.',
      ),
      _HealthSummaryTile(
        icon: Icons.water_drop_outlined,
        title: '혈당',
        value: '데이터 없음',
        level: _StatusLevel.warning,
        caption: '자가 기록 또는 연동이 필요합니다.',
      ),
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('건강 요약', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          SegmentedButton<_HealthRange>(
            segments: const [
              ButtonSegment(value: _HealthRange.today, label: Text('오늘')),
              ButtonSegment(value: _HealthRange.week, label: Text('7일')),
              ButtonSegment(value: _HealthRange.month, label: Text('30일')),
            ],
            selected: _selectedRange,
            onSelectionChanged: (value) => setState(() => _selectedRange = value),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: summaryTiles.map((tile) => _HealthSummaryCard(data: tile)).toList(),
          ),
          const SizedBox(height: 20),
          Card(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
            child: ListTile(
              leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
              title: const Text('건강 이상 신호를 수집하는 중입니다.'),
              subtitle: const Text('Health Connect와 웨어러블 데이터를 연동하면 이상 징후를 자동으로 알려드릴게요.'),
              trailing: TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('데이터 연동 후 주치의 공유 기능을 제공할 예정입니다.')),
                ),
                child: const Text('연동 가이드'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('걸음수 추세'),
                  subtitle: const Text('지난 7일 합계와 일별 추세를 확인합니다.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StepsPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bedtime_outlined),
                  title: const Text('수면 패턴'),
                  subtitle: const Text('수면 단계와 방해 요인을 확인합니다.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SleepPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.monitor_weight_outlined),
                  title: const Text('체중 · 체성분'),
                  subtitle: const Text('지난 4주간 변화를 간단히 확인합니다.'),
                  trailing: const Icon(Icons.insert_chart_outlined),
                  onTap: () => _showWip(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bloodtype_outlined),
                  title: const Text('혈압 리포트'),
                  subtitle: const Text('주간 평균과 측정 가이드를 제공합니다.'),
                  trailing: const Icon(Icons.insert_chart_outlined),
                  onTap: () => _showWip(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.water_drop_outlined),
                  title: const Text('혈당 메모'),
                  subtitle: const Text('식전 · 식후 기록을 간단히 정리합니다.'),
                  trailing: const Icon(Icons.edit_note_outlined),
                  onTap: () => _showWip(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('요·대변 검사'),
                  subtitle: const Text('자가 검사 후 결과를 기록하세요.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showWip(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('오늘의 코치'),
              subtitle: const Text('데이터가 연동되면 맞춤 활동 코칭을 안내해 드릴게요.'),
              trailing: TextButton(
                onPressed: () => _showWip(context),
                child: const Text('연동 방법'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWip(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('해당 기능은 추후 구현 예정입니다.')),
    );
  }
}

enum _HealthRange { today, week, month }

class _HealthSummaryTile {
  const _HealthSummaryTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.level,
    this.caption,
  });

  final IconData icon;
  final String title;
  final String value;
  final _StatusLevel level;
  final String? caption;
}

class _HealthSummaryCard extends StatelessWidget {
  const _HealthSummaryCard({required this.data});

  final _HealthSummaryTile data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _statusChipStyle(data.level, scheme);

    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(data.icon, color: scheme.primary),
              const SizedBox(height: 8),
              Text(data.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                data.value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: style.background, borderRadius: BorderRadius.circular(12)),
                child: Text(style.label, style: TextStyle(color: style.foreground, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (data.caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(data.caption!, style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                              Home Control Page                             */
/* -------------------------------------------------------------------------- */
class HomeControlPage extends StatefulWidget {
  const HomeControlPage({super.key});

  @override
  State<HomeControlPage> createState() => _HomeControlPageState();
}

class _HomeControlPageState extends State<HomeControlPage> {
  final List<String> _zones = const ['전체', '침실', '거실'];
  int _selectedZone = 0;
  bool _lightsOn = true;
  double _targetTemperature = 23;
  bool _ventilationOn = false;
  bool _automationEnabled = true;
  bool _airPurifierAuto = true;
  double? _filterLifePercent;
  bool _curtainOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('방 / 존 선택', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: List.generate(
              _zones.length,
              (index) => ChoiceChip(
                label: Text(_zones[index]),
                selected: _selectedZone == index,
                onSelected: (value) => setState(() => _selectedZone = index),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('빠른 제어 패널', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('조명'),
                    subtitle: Text(_lightsOn ? '현재 켜짐' : '현재 꺼짐'),
                    value: _lightsOn,
                    onChanged: (value) => setState(() => _lightsOn = value),
                  ),
                  const Divider(),
                  Text('냉난방 온도 설정', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() {
                          _targetTemperature = ((_targetTemperature - 0.5).clamp(16.0, 30.0)).toDouble();
                        }),
                      ),
                      Expanded(
                        child: Center(
                          child: Text('${_targetTemperature.toStringAsFixed(1)}℃', style: theme.textTheme.titleLarge),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() {
                          _targetTemperature = ((_targetTemperature + 0.5).clamp(16.0, 30.0)).toDouble();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('환기'),
                    subtitle: Text(_ventilationOn ? '환기 팬 가동 중' : '꺼져 있음'),
                    value: _ventilationOn,
                    onChanged: (value) => setState(() => _ventilationOn = value),
                  ),
                  SwitchListTile(
                    title: const Text('자동화'),
                    subtitle: const Text('CO₂ · 미세먼지 · 온습도에 따라 자동 제어'),
                    value: _automationEnabled,
                    onChanged: (value) => setState(() => _automationEnabled = value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('자동화 규칙', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const ListTile(
                    leading: Icon(Icons.co2_outlined),
                    title: Text('CO₂가 1,200ppm 이상 → 환기 켜기'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.air_outlined),
                    title: Text('PM2.5가 35㎍/㎥ 초과 → 공기청정기 강풍'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.thermostat_outlined),
                    title: Text('온도가 27℃ 이상 → 냉방 1단계'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('공기청정기', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('자동 모드'),
                    subtitle: const Text('실내 공기질에 따라 자동 조절'),
                    value: _airPurifierAuto,
                    onChanged: (value) => setState(() => _airPurifierAuto = value),
                  ),
                  ListTile(
                    leading: const Icon(Icons.filter_alt_outlined),
                    title: Text(
                      _filterLifePercent == null
                          ? '필터 수명 정보 없음'
                          : '필터 수명 ${_filterLifePercent!.toStringAsFixed(0)}%',
                    ),
                    subtitle: Text(
                      _filterLifePercent == null
                          ? '공기청정기를 연동하면 필터 상태를 확인할 수 있습니다.'
                          : '교체 주기를 확인하세요.',
                    ),
                    trailing: TextButton(
                      onPressed: () => _showSnack(context, '기기 연동 후 필터 관리 링크를 제공할 예정입니다.'),
                      child: const Text('연동 안내'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Icon(_curtainOpen ? Icons.window_outlined : Icons.blinds_closed, size: 32),
              title: const Text('커튼 / 창문'),
              subtitle: Text(_curtainOpen ? '현재 열려 있음' : '현재 닫혀 있음'),
              trailing: FilledButton.tonal(
                onPressed: () => setState(() => _curtainOpen = !_curtainOpen),
                child: Text(_curtainOpen ? '닫기' : '열기'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _showSnack(context, '기기 목록을 새로고침합니다.'),
            icon: const Icon(Icons.sync),
            label: const Text('기기 상태 새로고침'),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/* -------------------------------------------------------------------------- */
/*                           Emergency Contacts Page                           */
/* -------------------------------------------------------------------------- */
class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key});

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  bool _fallDetectionEnabled = true;
  bool _shareLocation = true;

  final List<_EmergencyContact> _contacts = const [
    _EmergencyContact(name: '김보호', relation: '배우자', phone: '010-1234-5678'),
    _EmergencyContact(name: '이간병', relation: '간병인', phone: '010-9988-7766'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('갤럭시 워치 연동', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('낙상 감지'),
            subtitle: const Text('낙상 시 119와 보호자에게 자동 연락합니다.'),
            value: _fallDetectionEnabled,
            onChanged: (value) => setState(() => _fallDetectionEnabled = value),
          ),
          SwitchListTile(
            title: const Text('위치 공유'),
            subtitle: const Text('응급 상황 시 GPS 위치를 함께 전송합니다.'),
            value: _shareLocation,
            onChanged: (value) => setState(() => _shareLocation = value),
          ),
          const SizedBox(height: 20),
          Text('응급 연락처', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          ..._contacts.map(
            (contact) => Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('${contact.name} (${contact.relation})'),
                subtitle: Text(contact.phone),
                trailing: IconButton(
                  icon: const Icon(Icons.phone),
                  onPressed: () => _showSnack(context, '${contact.name}님에게 전화를 연결합니다.'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showSnack(context, '연락처 추가 화면은 추후 연결됩니다.'),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('연락처 추가'),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('응급 상황 대처법'),
              subtitle: const Text('119 신고 전에 호흡, 의식 상태를 확인하세요.'),
              trailing: TextButton(
                onPressed: () => _showSnack(context, '응급 매뉴얼은 추후 연결됩니다.'),
                child: const Text('자세히'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('응급 알림 테스트'),
            subtitle: const Text('보호자에게 테스트 메시지를 보냅니다.'),
            onTap: () => _showSnack(context, '테스트 알림을 전송했습니다.'),
          ),
          ListTile(
            leading: const Icon(Icons.medical_services_outlined),
            title: const Text('주치의에게 보내기'),
            subtitle: const Text('응급 리포트를 병원으로 전송합니다.'),
            onTap: () => _showSnack(context, '병원 전송은 추후 구현 예정입니다.'),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmergencyContact {
  const _EmergencyContact({required this.name, required this.relation, required this.phone});

  final String name;
  final String relation;
  final String phone;
}

/* -------------------------------------------------------------------------- */
/*                                  Settings                                  */
/* -------------------------------------------------------------------------- */
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSection(
            context,
            title: '계정 & 보안',
            tiles: [
              _settingsTile(context, icon: Icons.person_outline, title: '프로필', subtitle: '이름, 연락처, 프로필 이미지'),
              _settingsTile(context, icon: Icons.lock_outline, title: '비밀번호 변경', subtitle: '2단계 인증, 비밀번호 재설정'),
              _settingsTile(context, icon: Icons.logout, title: '로그아웃', subtitle: '앱에서 로그아웃합니다.'),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            title: '권한 & 데이터',
            tiles: [
              _settingsTile(context, icon: Icons.favorite_outline, title: '건강 데이터 범위', subtitle: '연동된 항목을 다시 선택합니다.'),
              _settingsTile(context, icon: Icons.download_outlined, title: '데이터 내보내기', subtitle: 'CSV / PDF로 내보내기'),
              _settingsTile(context, icon: Icons.delete_outline, title: '데이터 삭제', subtitle: '수집 중단 및 데이터 삭제 요청'),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            title: '연동',
            tiles: [
              _settingsTile(context, icon: Icons.home_outlined, title: 'Home Assistant', subtitle: '토큰 및 엔드포인트 관리'),
              _settingsTile(context, icon: Icons.watch_outlined, title: '웨어러블 기기', subtitle: '연동된 기기를 확인합니다.'),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            title: '고지',
            tiles: [
              _settingsTile(context, icon: Icons.privacy_tip_outlined, title: '개인정보 처리방침', subtitle: '법적 고지를 확인합니다.'),
              _settingsTile(context, icon: Icons.article_outlined, title: '오픈소스 라이선스', subtitle: '사용 중인 라이브러리 정보를 확인합니다.'),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            color: theme.colorScheme.surfaceVariant,
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('앱 버전 0.1.0'),
              subtitle: Text('FinalHealthCheck Demo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required List<Widget> tiles}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i != tiles.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$title" 화면은 추후 연결됩니다.')),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                        Health base & detail pages                          */
/* -------------------------------------------------------------------------- */
abstract class _HealthStatefulPage extends StatefulWidget {
  const _HealthStatefulPage({super.key});
}

abstract class _HealthState<T extends _HealthStatefulPage> extends State<T> {
  bool authorized = false;
  String? errorMsg;

  List<HealthDataType> get types;

  Health get health => HealthController.I.health;

  @override
  void initState() {
    super.initState();
    _initHealthFlow();
  }

  Future<void> _initHealthFlow() async {
    try {
      await HealthController.I.ensureConfigured();
      final has = await HealthController.I.hasPermsFor(types);
      if (!has) {
        final ok = await HealthController.I.requestPermsFor(types);
        authorized = ok;
        errorMsg = ok ? null : '필요한 권한을 허용해 주세요.';
      } else {
        authorized = true;
        errorMsg = null;
      }
      if (authorized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) onAuthorizationReady();
        });
      }
    } catch (e) {
      errorMsg = '권한 초기화 오류: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  @protected
  void onAuthorizationReady() {}

  Future<void> refreshAuthorization() async {
    try {
      final has = await HealthController.I.hasPermsFor(types);
      if (!mounted) return;
      setState(() {
        authorized = has;
        if (has) {
          errorMsg = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) onAuthorizationReady();
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMsg = '권한 확인 오류: $e';
      });
    }
  }
}

class StepsPage extends _HealthStatefulPage {
  const StepsPage({super.key});

  @override
  State<StepsPage> createState() => _StepsPageState();
}

class _StepsPageState extends _HealthState<StepsPage> {
  bool _loading = false;
  int _todaySteps = 0;
  List<_DailyStepsEntry> _history = const [];
  List<BarChartGroupData> _barGroups = const [];

  @override
  List<HealthDataType> get types => const [HealthDataType.STEPS];

  @override
  void onAuthorizationReady() {
    _loadDailySteps();
  }

  Future<void> _loadDailySteps() async {
    if (_loading || !authorized) return;

    setState(() {
      _loading = true;
      errorMsg = null;
    });

    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final entries = <_DailyStepsEntry>[];
      int todaySteps = 0;

      for (int i = 6; i >= 0; i--) {
        final dayStart = startOfToday.subtract(Duration(days: i));
        final dayEnd = dayStart.add(const Duration(days: 1));
        final stepsForDay = await _sumStepsForInterval(dayStart, dayEnd);

        entries.add(_DailyStepsEntry(date: dayStart, steps: stepsForDay));
        if (i == 0) todaySteps = stepsForDay;
      }

      if (!mounted) return;
      setState(() {
        _history = entries;
        _todaySteps = todaySteps;
        _barGroups = _prepareBarChartData(entries);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        errorMsg = '걸음 수를 불러오지 못했습니다: $e';
      });
    }
  }

  Future<int> _sumStepsForInterval(DateTime startTime, DateTime endTime) async {
    final aggregated = await health.getTotalStepsInInterval(startTime, endTime);
    final aggregatedSteps = _tryParseStepCount(aggregated);
    if (aggregatedSteps != null) {
      return aggregatedSteps;
    }

    final points = await health.getHealthDataFromTypes(
      types: const [HealthDataType.STEPS],
      startTime: startTime,
      endTime: endTime,
    );

    int total = 0;
    for (final point in points) {
      final parsed = _tryParseStepCount(point.value);
      if (parsed != null) {
        total += parsed;
      }
    }
    return total;
  }

  int? _tryParseStepCount(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    if (raw is num) return raw.round();
    if (raw is String) {
      final parsed = num.tryParse(raw);
      if (parsed != null) return parsed.round();
    }

    try {
      final dynamic numeric = raw.numericValue;
      if (numeric is num) return numeric.round();
    } catch (_) {}

    try {
      final dynamic value = raw.value;
      if (!identical(value, raw)) {
        final nested = _tryParseStepCount(value);
        if (nested != null) return nested;
      }
    } catch (_) {}

    try {
      final dynamic intValue = raw.intValue;
      if (intValue is num) return intValue.round();
    } catch (_) {}

    try {
      final dynamic doubleValue = raw.doubleValue;
      if (doubleValue is num) return doubleValue.round();
    } catch (_) {}

    try {
      final dynamic json = raw.toJson();
      if (!identical(json, raw)) {
        final parsed = _tryParseStepCount(json);
        if (parsed != null) return parsed;
      }
    } catch (_) {}

    if (raw is Map) {
      for (final key in ['numericValue', 'value', 'steps', 'count', 'intValue', 'doubleValue', 'quantity']) {
        if (raw.containsKey(key)) {
          final parsed = _tryParseStepCount(raw[key]);
          if (parsed != null) return parsed;
        }
      }
      for (final entry in raw.values) {
        if (entry is num) return entry.round();
        if (entry is Map || entry is Iterable) {
          final parsed = _tryParseStepCount(entry);
          if (parsed != null) return parsed;
        }
      }
    }

    if (raw is Iterable) {
      int sum = 0;
      bool found = false;
      for (final item in raw) {
        final parsed = _tryParseStepCount(item);
        if (parsed != null) {
          sum += parsed;
          found = true;
        }
      }
      if (found) return sum;
    }

    return null;
  }

  List<BarChartGroupData> _prepareBarChartData(List<_DailyStepsEntry> entries) {
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entry.steps.toDouble(),
              color: Colors.teal,
              width: 16,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  Widget _buildBottomTitles(double value, TitleMeta meta) {
    final index = value.toInt();
    if (index < 0 || index >= _history.length) return const SizedBox.shrink();
    final date = _history[index].date;
    final label = DateFormat('E').format(date);
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 6,
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _buildLeftTitles(double value, TitleMeta meta) {
    if (value == meta.max || value == meta.min) {
      return const SizedBox.shrink();
    }
    if (value % 5000 != 0) {
      return const SizedBox.shrink();
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 6,
      child: Text(NumberFormat.compact().format(value.toInt()), style: const TextStyle(fontSize: 10)),
    );
  }

  double _maxY() {
    if (_history.isEmpty) return 10000;
    final maxSteps = _history.fold<int>(0, (maxVal, entry) => entry.steps > maxVal ? entry.steps : maxVal);
    if (maxSteps == 0) return 5000;
    return (maxSteps * 1.2).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final numberFormatter = NumberFormat('#,###');
    final totalSteps = _history.fold<int>(0, (sum, entry) => sum + entry.steps);
    final averageSteps = _history.isEmpty ? 0 : (totalSteps / _history.length).round();
    final bestDay = _history.isEmpty
        ? null
        : _history.reduce((current, next) => next.steps > current.steps ? next : current);
    final quietDay = _history.isEmpty
        ? null
        : _history.reduce((current, next) => next.steps < current.steps ? next : current);
    final double goalProgress = (_todaySteps / 10000).clamp(0.0, 1.0);
    final remainingSteps = _todaySteps >= 10000 ? 0 : 10000 - _todaySteps;

    String insightHeadline;
    String? insightSupporting;
    if (_history.isEmpty) {
      insightHeadline = '최근 7일 걸음 데이터가 아직 없어요.';
      insightSupporting = 'Health Connect와 동기화되면 추세를 분석해 드릴게요.';
    } else if (_todaySteps == 0) {
      insightHeadline = '오늘 걸음이 아직 집계되지 않았어요.';
      insightSupporting = '가벼운 산책으로 몸을 깨워보는 건 어떨까요?';
    } else {
      final diffFromAverage = _todaySteps - averageSteps;
      if (diffFromAverage >= 1000) {
        insightHeadline = '평균보다 ${numberFormatter.format(diffFromAverage)}걸음 더 걸었어요!';
        insightSupporting = '좋은 페이스예요. 오늘은 스트레칭으로 마무리해 보세요.';
      } else if (diffFromAverage <= -1000) {
        insightHeadline = '평균보다 ${numberFormatter.format(diffFromAverage.abs())}걸음 적어요.';
        insightSupporting = '짧은 산책이나 계단 오르기로 활동량을 채워보세요.';
      } else {
        insightHeadline = '평균과 비슷한 활동량이에요.';
        insightSupporting = '꾸준함을 유지하면 회복에 도움이 돼요.';
      }
    }

    String? trendSummary;
    if (bestDay != null && quietDay != null && bestDay.date != quietDay.date) {
      trendSummary =
          '${_formatDayLabel(bestDay.date)}에는 ${numberFormatter.format(bestDay.steps)}걸음으로 가장 활발했어요.';
      if (quietDay.steps < bestDay.steps) {
        trendSummary +=
            '\n${_formatDayLabel(quietDay.date)}에는 ${numberFormatter.format(quietDay.steps)}걸음으로 휴식이 필요해 보였어요.';
      }
    }

    final insightDetail = [
      if (insightSupporting != null) insightSupporting!,
      if (trendSummary != null) trendSummary,
    ].join('\n');

    return Scaffold(
      appBar: AppBar(title: const Text('7일 걸음수 추세')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(
                      authorized ? Icons.check_circle_outline : Icons.error_outline,
                      color: authorized ? Colors.teal : Theme.of(context).colorScheme.error,
                    ),
                    label: Text('권한: ${authorized ? '허용됨' : '미허용'}'),
                  ),
                  if (authorized && _history.isNotEmpty)
                    Chip(label: Text('최근 7일 총 ${numberFormatter.format(totalSteps)}걸음')),
                  if (authorized && _history.isNotEmpty)
                    Chip(label: Text('7일 평균 ${numberFormatter.format(averageSteps)}걸음')),
                  if (authorized && bestDay != null)
                    Chip(
                      label: Text(
                        '최고 ${numberFormatter.format(bestDay.steps)}걸음 (${_weekdaySymbols[(bestDay.date.weekday - 1) % _weekdaySymbols.length]})',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: authorized ? _loadDailySteps : null,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: const Text('걸음수 불러오기'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: refreshAuthorization,
                    child: const Text('권한 다시 확인'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!authorized)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Health Connect 권한을 허용해야 걸음 데이터를 볼 수 있습니다.'),
                  ),
                ),
              if (authorized) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_walk_outlined),
                    title: Text('오늘은 ${numberFormatter.format(_todaySteps)}걸음 걸었습니다.'),
                    subtitle: const Text('걷기 목표는 건강 관리의 기본이에요.'),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading && _barGroups.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                if (!_loading && _barGroups.isNotEmpty)
                  SizedBox(
                    height: 260,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
                        child: BarChart(
                          BarChartData(
                            barGroups: _barGroups,
                            maxY: _maxY(),
                            alignment: BarChartAlignment.spaceAround,
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: _buildBottomTitles)),
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: _buildLeftTitles)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5000),
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: Theme.of(context).colorScheme.primary,
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  if (group.x < 0 || group.x >= _history.length) return null;
                                  final entry = _history[group.x];
                                  return BarTooltipItem(
                                    '${DateFormat('MMM d').format(entry.date)}\n',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    children: [
                                      TextSpan(
                                        text: '${numberFormatter.format(entry.steps)} 걸음',
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_loading && _barGroups.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '최근 7일 걸음 데이터가 없습니다. Health Connect에 데이터가 있는지 확인해 주세요.',
                      ),
                    ),
                  ),
                if (!_loading && _history.isNotEmpty)
                  Column(
                    children: [
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.trending_up),
                              title: const Text('7일 평균 활동량'),
                              subtitle: Text('${numberFormatter.format(averageSteps)}걸음'),
                            ),
                            if (bestDay != null) const Divider(height: 1),
                            if (bestDay != null)
                              ListTile(
                                leading: const Icon(Icons.arrow_circle_up_outlined),
                                title: const Text('가장 활발했던 날'),
                                subtitle: Text(
                                  '${_formatDayLabel(bestDay.date)} · ${numberFormatter.format(bestDay.steps)}걸음',
                                ),
                              ),
                            if (quietDay != null) const Divider(height: 1),
                            if (quietDay != null)
                              ListTile(
                                leading: const Icon(Icons.arrow_circle_down_outlined),
                                title: const Text('휴식이 많았던 날'),
                                subtitle: Text(
                                  '${_formatDayLabel(quietDay.date)} · ${numberFormatter.format(quietDay.steps)}걸음',
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('오늘 목표 진행도', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: goalProgress,
                                  minHeight: 10,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text('10,000걸음 목표의 ${(goalProgress * 100).clamp(0, 100).round()}%를 달성했어요.'),
                              if (remainingSteps > 0)
                                Text(
                                  '약 ${numberFormatter.format(remainingSteps)}걸음을 더 걸으면 목표를 채울 수 있어요.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (remainingSteps == 0)
                                Text(
                                  '오늘 목표를 모두 달성했어요! 충분한 스트레칭으로 몸을 풀어보세요.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Column(
                          children: [
                            const ListTile(
                              leading: Icon(Icons.calendar_view_week_outlined),
                              title: Text('일별 기록'),
                              subtitle: Text('최근 7일간의 변화'),
                            ),
                            const Divider(height: 1),
                            for (int i = 0; i < _history.length; i++) ...[
                              ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    _weekdaySymbols[(_history[i].date.weekday - 1) % _weekdaySymbols.length],
                                  ),
                                ),
                                title: Text(_formatDayLabel(_history[i].date)),
                                subtitle: Text(_differenceLabel(i, numberFormatter)),
                                trailing: Text('${numberFormatter.format(_history[i].steps)}걸음'),
                              ),
                              if (i != _history.length - 1) const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                if (!_loading && _history.isEmpty)
                  Card(
                    child: Column(
                      children: const [
                        ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('최근 7일 걸음 데이터가 없습니다.'),
                          subtitle: Text('Health Connect에 데이터가 있는지 확인한 뒤 다시 동기화해 주세요.'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                  child: ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: Text(insightHeadline),
                    subtitle: insightDetail.isEmpty ? null : Text(insightDetail),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _weekdaySymbols = ['월', '화', '수', '목', '금', '토', '일'];

  String _formatDayLabel(DateTime date) {
    final symbol = _weekdaySymbols[(date.weekday - 1) % _weekdaySymbols.length];
    return '${date.month}월 ${date.day}일 ($symbol)';
  }

  String _differenceLabel(int index, NumberFormat formatter) {
    if (index == 0) return '기준 데이터 없음';
    final diff = _history[index].steps - _history[index - 1].steps;
    if (diff == 0) return '— 변화 없음';
    if (diff > 0) {
      return '▲ +${formatter.format(diff)}걸음';
    }
    return '▼ ${formatter.format(diff.abs())}걸음';
  }
}

class _DailyStepsEntry {
  const _DailyStepsEntry({required this.date, required this.steps});

  final DateTime date;
  final int steps;
}

class SleepPage extends _HealthStatefulPage {
  const SleepPage({super.key});

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends _HealthState<SleepPage> {
  Duration totalSleep = Duration.zero;
  List<HealthDataPoint> stages = const [];
  bool _loading = false;

  @override
  List<HealthDataType> get types => const [
        HealthDataType.SLEEP_SESSION,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_IN_BED,
      ];

  @override
  void onAuthorizationReady() {
    _loadSleep();
  }

  Future<void> _loadSleep() async {
    if (!authorized || _loading) return;

    setState(() {
      _loading = true;
      errorMsg = null;
    });

    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final dayStart = startOfToday.subtract(const Duration(days: 1));
      final dayEnd = startOfToday;

      final sessions = await health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_SESSION],
        startTime: dayStart,
        endTime: dayEnd,
      );

      Duration sum = Duration.zero;
      for (final s in sessions) {
        final from = s.dateFrom;
        final to = s.dateTo;
        if (from != null && to != null) {
          sum += to.difference(from);
        }
      }

      final stageTypes = const <HealthDataType>[
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_IN_BED,
      ];
      final stagePoints = await health.getHealthDataFromTypes(
        types: stageTypes,
        startTime: dayStart,
        endTime: dayEnd,
      );

      if (!mounted) return;
      setState(() {
        totalSleep = sum;
        stages = stagePoints;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        errorMsg = '수면 데이터를 불러오지 못했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = totalSleep.inHours;
    final minutes = totalSleep.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(title: const Text('수면 패턴')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    avatar: Icon(
                      authorized ? Icons.check_circle_outline : Icons.error_outline,
                      color: authorized ? Colors.teal : Theme.of(context).colorScheme.error,
                    ),
                    label: Text('권한: ${authorized ? '허용됨' : '미허용'}'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: authorized ? _loadSleep : null,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: const Text('어제 수면 불러오기'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: refreshAuthorization,
                    child: const Text('권한 다시 확인'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.nightlight_round),
                  title: Text('어제 총 수면: ${hours}시간 ${minutes}분'),
                  subtitle: const Text('의료적 판단은 의료진과 상의하세요.'),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              if (!_loading && stages.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('수면 단계 데이터를 찾지 못했습니다. 웨어러블 연동 상태를 확인해 주세요.'),
                ),
              if (!_loading && stages.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      for (final stage in stages)
                        ListTile(
                          leading: const Icon(Icons.timeline_outlined),
                          title: Text(stage.typeString),
                          subtitle: Text(_stageLabel(stage)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _stageLabel(HealthDataPoint point) {
    final from = point.dateFrom?.toLocal();
    final to = point.dateTo?.toLocal();
    final buffer = StringBuffer();
    if (from != null && to != null) {
      buffer.write('${DateFormat('HH:mm').format(from)} ~ ${DateFormat('HH:mm').format(to)}');
      final duration = to.difference(from);
      buffer.write(' (${duration.inMinutes}분)');
    }
    if (point.value != null) {
      buffer.write(' • ${point.value}');
    }
    return buffer.isEmpty ? '기록 없음' : buffer.toString();
  }
}
