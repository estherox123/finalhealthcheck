import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'health_controller.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wellness Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                            HealthController(전역)                           */
/* -------------------------------------------------------------------------- */
class HealthController {
  HealthController._();
  static final HealthController I = HealthController._();

  final Health health = Health();
  bool _configured = false;

  Future<void> ensureConfigured() async {
    if (_configured) return;
    await health.configure(); // 권한 콜백 런처 등록
    _configured = true;
  }

  Future<bool> hasPermsFor(List<HealthDataType> types) async {
    final reads = List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);
    return await health.hasPermissions(types, permissions: reads) ?? false;
  }

  Future<bool> requestPermsFor(List<HealthDataType> types) async {
    // 일부 단말 보완
    try {
      await HealthController.I.health.installHealthConnect();
    } catch (_) {
      // installHealthConnect() 미지원 기기에서도 에러 없이 넘어가도록
    }

    // (선택) 가용성 점검. 미가용이면 권한 요청이 먹히지 않습니다.
    final available = await HealthController.I.health.isHealthConnectAvailable();
    if (!available) {
      // 사용자에게 Health Connect를 설치/활성화하라고 알림
      return false;
    }

    final reads = List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);
    final had = await hasPermsFor(types);
    if (had) return true;

    final ok = await health.requestAuthorization(types, permissions: reads);
    final after = await hasPermsFor(types); // 요청 직후 재확인(중요)
    return ok && after;
  }
}

/* -------------------------------------------------------------------------- */
/*                                    Home                                    */
/* -------------------------------------------------------------------------- */
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Wellness')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            _BigButton(
              label: '헬스',
              icon: Icons.favorite_outline,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthMenuPage()),
              ),
            ),
            const SizedBox(height: 20),
            _BigButton(
              label: 'IoT',
              icon: Icons.devices_other_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IotWipPage()),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _BigButton({required this.label, required this.icon, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                   IoT WIP                                  */
/* -------------------------------------------------------------------------- */
class IotWipPage extends StatelessWidget {
  const IotWipPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IoT')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined, size: 72),
            const SizedBox(height: 12),
            const Text('개발중', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('뒤로가기'),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                 Health Menu                                */
/* -------------------------------------------------------------------------- */
class HealthMenuPage extends StatelessWidget {
  const HealthMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('헬스')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            _BigButton(
              label: '걸음수',
              icon: Icons.directions_walk_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StepsPage()),
              ),
            ),
            const SizedBox(height: 20),
            _BigButton(
              label: '수면패턴',
              icon: Icons.bedtime_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SleepPage()),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                            Health 공통 베이스 클래스                        */
/* -------------------------------------------------------------------------- */
abstract class _HealthStatefulPage extends StatefulWidget {
  const _HealthStatefulPage({super.key});
}

abstract class _HealthState<T extends _HealthStatefulPage> extends State<T> {
  bool authorized = false;
  String? errorMsg;

  /// 각 페이지에서 필요한 타입만 정의해준다.
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
      } else {
        authorized = true;
      }
    } catch (e) {
      errorMsg = '권한 초기화 오류: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }
}

/* -------------------------------------------------------------------------- */
/*                                  Steps Page                                */
/* -------------------------------------------------------------------------- */
class StepsPage extends _HealthStatefulPage {
  const StepsPage({super.key});
  @override
  State<StepsPage> createState() => _StepsPageState();
}

class _StepsPageState extends _HealthState<StepsPage> {
  int totalSteps7d = 0;

  @override
  List<HealthDataType> get types => const [HealthDataType.STEPS];

  Future<void> _load() async {
    final has = await HealthController.I.hasPermsFor(const [HealthDataType.STEPS]);
    debugPrint('HAS READ_STEPS? $has');

    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 7));

    int total = 0;

    // 1) ✅ 집계 API (소스에 따라 이게 잘 동작)
    final agg = await HealthController.I.health.getTotalStepsInInterval(start, now);
    if (agg != null) {
      total = agg;
    } else {
      // 2) 폴백: 포인트를 직접 합산
      final points = await health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: now,
      );
      for (final p in points) {
        final v = (p.value is num) ? (p.value as num).toDouble() : 0.0;
        total += v.round();
      }
    }

    if (!mounted) return;
    setState(() => totalSteps7d = total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('걸음수')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errorMsg != null)
              Text(errorMsg!, style: const TextStyle(color: Colors.red)),
            Text('권한: ${authorized ? "허용됨" : "미허용"}'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: authorized ? _load : null,
                  child: const Text('지난 7일 총 걸음수 불러오기'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    final has = await HealthController.I.hasPermsFor(types);
                    if (!mounted) return;
                    setState(() => authorized = has);
                  },
                  child: const Text('권한 다시 확인'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('총합: $totalSteps7d', style: const TextStyle(fontSize: 22)),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                  Sleep Page                                */
/* -------------------------------------------------------------------------- */
class SleepPage extends _HealthStatefulPage {
  const SleepPage({super.key});
  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends _HealthState<SleepPage> {
  Duration totalSleep = Duration.zero;
  List<HealthDataPoint> stages = [];

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

  Future<void> _load() async {
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
      final a = s.dateFrom, b = s.dateTo;
      if (a != null && b != null) sum += b.difference(a);
    }

    final stageTypes = const <HealthDataType>[
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_AWAKE,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_IN_BED,
    ];
    final st = await health.getHealthDataFromTypes(
      types: stageTypes,
      startTime: dayStart,
      endTime: dayEnd,
    );

    if (!mounted) return;
    setState(() {
      totalSleep = sum;
      stages = st;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hours = totalSleep.inMinutes ~/ 60;
    final mins = totalSleep.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(title: const Text('수면패턴')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errorMsg != null)
              Text(errorMsg!, style: const TextStyle(color: Colors.red)),
            Text('권한: ${authorized ? "허용됨" : "미허용"}'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: authorized ? _load : null,
                  child: const Text('어제 수면패턴 불러오기'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    final has = await HealthController.I.hasPermsFor(types);
                    if (!mounted) return;
                    setState(() => authorized = has);
                  },
                  child: const Text('권한 다시 확인'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('어제 총 수면: $hours시간 $mins분', style: const TextStyle(fontSize: 18)),
            const Divider(height: 28),
            const Text('수면 단계 (어제):'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: stages.length,
                itemBuilder: (_, i) {
                  final p = stages[i];
                  final a = p.dateFrom?.toLocal();
                  final b = p.dateTo?.toLocal();
                  return ListTile(
                    dense: true,
                    title: Text(p.typeString),
                    subtitle: Text('${a ?? '-'} ~ ${b ?? '-'}  •  ${p.value}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
