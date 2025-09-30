import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import 'base_health_page.dart';
import 'health_controller.dart';

class SleepDetailPage extends HealthStatefulPage {
  const SleepDetailPage({super.key});
  @override
  State<SleepDetailPage> createState() => _SleepDetailPageState();
}

class _SleepDetailPageState extends HealthState<SleepDetailPage> {
  @override
  List<HealthDataType> get types => const [HealthDataType.SLEEP_SESSION];

  Duration totalSleep = Duration.zero;
  List<HealthDataPoint> stages = [];
  bool loading = false;

  static const List<HealthDataType> _stageTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_IN_BED,
  ];

  Future<void> _load() async {
    if (!authorized || loading) return;
    setState(() => loading = true);

    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final dayStart = startOfToday.subtract(const Duration(days: 1));
      final dayEnd = startOfToday;

      // 세션 합산 (네임드 인자)
      final sessions = await health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_SESSION],
        startTime: dayStart,
        endTime: dayEnd,
      );
      var sum = Duration.zero;
      for (final s in sessions) {
        final a = s.dateFrom, b = s.dateTo;
        if (a != null && b != null) sum += b.difference(a);
      }

      // 단계 (권한 없으면 빈 리스트 가능)
      final st = await health.getHealthDataFromTypes(
        types: _stageTypes,
        startTime: dayStart,
        endTime: dayEnd,
      );

      if (!mounted) return;
      setState(() {
        totalSleep = sum;
        stages = st;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMsg = '수면 로딩 실패: $e';
      });
    }
  }

  Future<void> _requestStagePerms() async {
    await HealthController.I.ensureConfigured();
    final ok1 = await HealthController.I.requestPermsFor(const [HealthDataType.SLEEP_SESSION]);
    final ok2 = await HealthController.I.requestPermsFor(_stageTypes);
    if (!mounted) return;
    setState(() => authorized = ok1 || ok2);
  }

  @override
  Widget build(BuildContext context) {
    final h = totalSleep.inMinutes ~/ 60;
    final m = totalSleep.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(title: const Text('수면 패턴')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errorMsg != null)
              Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Text('권한: ${authorized ? "허용됨" : "미허용"}'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(onPressed: authorized && !loading ? _load : null, child: const Text('어제 수면 불러오기')),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    await HealthController.I.ensureConfigured();
                    final has = await HealthController.I.hasPermsFor(types);
                    if (!mounted) return;
                    setState(() => authorized = has);
                  },
                  child: const Text('권한 다시 확인'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _requestStagePerms, child: const Text('수면(단계) 권한 요청')),
              ],
            ),
            const SizedBox(height: 16),
            Text('어제 총 수면: ${h}시간 ${m}분', style: const TextStyle(fontSize: 18)),
            const Divider(height: 28),
            const Text('수면 단계 (어제):'),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                itemCount: stages.length,
                itemBuilder: (_, i) {
                  final p = stages[i];
                  final a = p.dateFrom?.toLocal();
                  final b = p.dateTo?.toLocal();
                  return ListTile(
                    dense: true,
                    title: Text(p.typeString),
                    subtitle: Text('${a ?? '-'} ~ ${b ?? '-'} • ${p.value}'),
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
