import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'health_controller.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:fl_chart/fl_chart.dart'; // Example charting library

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
  Map<String, int> dailySteps = {};
  bool isLoadingData = false;
  int todaysSteps = 0;

  List<BarChartGroupData> barGroups = [];
  List<String> dateLabelsForChart = [];

  @override
  List<HealthDataType> get types => const [HealthDataType.STEPS];

  @override
  String get pageSpecificFeatureName => "daily step count tracking";

  @override
  void initState() {
    super.initState();
    // This function will be called once when the widget is inserted into the tree.
    // We use addPostFrameCallback to ensure that the first frame is built
    // and any initial state from the base class (like 'authorized') is likely set.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if the widget is still mounted and if permissions are granted
      if (mounted && authorized) {
        // This is equivalent to "pressing" the refresh button automatically
        // when the page is entered and permissions are already granted.
        _loadDailySteps();
      } else if (mounted && !authorized) {
        // If not authorized, the UI should guide the user to grant permissions.
        // The _loadDailySteps() method itself also checks for 'authorized'
        // as a safeguard.
        debugPrint("StepsPage: Not authorized on initial load. Steps will not be fetched automatically.");
      }
    });
  }

  // If your _HealthState base class has a way to notify subclasses when 'authorized'
  // status changes *after* initState (e.g., user grants permissions via a dialog
  // managed by the base class while this page is visible), you would also call
  // _loadDailySteps() there. For example:
  //
  // void onPermissionsGrantedByBase() { // Imaginary method called by base class
  //   if (mounted && authorized) {
  //     _loadDailySteps();
  //   }
  // }


  Future<void> _loadDailySteps() async {
    // Prevent multiple simultaneous loads or loading if not authorized
    if (isLoadingData || !authorized) {
      if (!authorized) {
        debugPrint("StepsPage: _loadDailySteps called but not authorized.");
      }
      if (isLoadingData) {
        debugPrint("StepsPage: _loadDailySteps called but already loading data.");
      }
      return;
    }

    debugPrint("StepsPage: Starting to load daily steps...");
    setState(() {
      isLoadingData = true;
      // Clear previous data
      dailySteps.clear();
      barGroups.clear();
      dateLabelsForChart.clear();
      todaysSteps = 0;
      // If your base class uses 'errorMsg', you might want to clear data-loading specific errors here
      // errorMsg = null;
    });

    try {
      final now = DateTime.now();
      Map<String, int> newDailySteps = {};

      // Fetch today's steps for prominent display
      final todayStartTime = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final todayEndTime = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      int currentTodaysSteps = 0;
      final aggregatedTodaysSteps = await health.getTotalStepsInInterval(todayStartTime, todayEndTime);
      if (aggregatedTodaysSteps != null) {
        currentTodaysSteps = aggregatedTodaysSteps;
      } else {
        final points = await health.getHealthDataFromTypes(
          types: const [HealthDataType.STEPS],
          startTime: todayStartTime,
          endTime: todayEndTime,
        );
        for (final p in points) {
          final v = (p.value is num) ? (p.value as num).toDouble() : 0.0;
          currentTodaysSteps += v.round();
        }
      }
      // Update today's steps for the UI immediately if mounted
      if (mounted) {
        setState(() {
          todaysSteps = currentTodaysSteps;
        });
      }

      // Load 7-day history for the chart
      for (int i = 6; i >= 0; i--) {
        final dayToFetch = now.subtract(Duration(days: i));
        final startTime = DateTime(dayToFetch.year, dayToFetch.month, dayToFetch.day, 0, 0, 0);
        final endTime = DateTime(dayToFetch.year, dayToFetch.month, dayToFetch.day, 23, 59, 59, 999);
        int stepsForDay = 0;

        if (i == 0) { // Today
          stepsForDay = currentTodaysSteps; // Reuse already fetched value
        } else {
          final aggregatedSteps = await health.getTotalStepsInInterval(startTime, endTime);
          if (aggregatedSteps != null) {
            stepsForDay = aggregatedSteps;
          } else {
            final points = await health.getHealthDataFromTypes(
              types: const [HealthDataType.STEPS],
              startTime: startTime,
              endTime: endTime,
            );
            for (final p in points) {
              final v = (p.value is num) ? (p.value as num).toDouble() : 0.0;
              stepsForDay += v.round();
            }
          }
        }
        final dateKey = DateFormat('yyyy-MM-dd').format(startTime);
        newDailySteps[dateKey] = stepsForDay;
      }

      if (!mounted) return;
      setState(() {
        final sortedKeys = newDailySteps.keys.toList()..sort();
        dailySteps = {for (var k in sortedKeys) k: newDailySteps[k]!};
        _prepareBarChartData(); // Prepare data for the chart
        isLoadingData = false;
        debugPrint("StepsPage: Daily steps loaded successfully.");
      });
    } catch (e) {
      debugPrint("StepsPage: Error loading daily steps: $e");
      if (!mounted) return;
      setState(() {
        isLoadingData = false;
        // If errorMsg is managed by your base _HealthState for permissions,
        // you might set a specific data loading error here, or have a separate one.
        // For now, we assume the base errorMsg might be used or you handle errors in UI.
        // errorMsg = "Failed to load step data. Please try again.";
      });
    }
  }

  // --- Methods for chart data preparation and titles ---
  // _prepareBarChartData, bottomTitles, leftTitles, _getChartMaxY
  // (These methods remain unchanged from the previous version)

  void _prepareBarChartData() {
    barGroups.clear();
    dateLabelsForChart.clear();
    if (dailySteps.isEmpty) return;

    final sortedEntries = dailySteps.entries.toList()..sort((e1, e2) => e1.key.compareTo(e2.key));

    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final date = DateFormat('yyyy-MM-dd').parse(entry.key);
      final steps = entry.value.toDouble();

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: steps,
              color: Colors.teal,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
      dateLabelsForChart.add(DateFormat('E').format(date));
    }
  }

  Widget bottomTitles(double value, TitleMeta meta) {
    final index = value.toInt();
    if (index < 0 || index >= dateLabelsForChart.length) return Container();
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 4,
      child: Text(dateLabelsForChart[index], style: const TextStyle(fontSize: 10)),
    );
  }

  Widget leftTitles(double value, TitleMeta meta) {
    if (value == meta.max || value == meta.min) {}
    else if (value % 5000 != 0) return Container();
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 6,
      child: Text(NumberFormat.compact().format(value.toInt()), style: const TextStyle(fontSize: 10)),
    );
  }

  double _getChartMaxY() {
    if (dailySteps.isEmpty) return 10000;
    final maxSteps = dailySteps.values.fold(0, (maxVal, v) => v > maxVal ? v : maxVal).toDouble();
    if (maxSteps == 0) return 5000;
    return (maxSteps * 1.2).ceilToDouble();
  }

  // --- build() method ---
  // (This method remains largely unchanged from the previous version where the chart was working
  // and today's step count was displayed. The key is that _loadDailySteps is now called from initState)

  @override
  Widget build(BuildContext context) {
    final numberFormatter = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(title: const Text('Past 7 Days Steps')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Display error messages from base class, if any
            if (errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(errorMsg!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
              ),
            // Display permission status from base class
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Permissions: ${authorized ? "Granted" : "Denied / Not Requested"}', textAlign: TextAlign.center),
            ),
            // Manual refresh button (still useful)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: authorized && !isLoadingData ? _loadDailySteps : null,
                  icon: isLoadingData ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                  label: const Text('Load/Refresh Steps'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Display Today's Step Count
            if (authorized && !isLoadingData)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  "오늘은 ${numberFormatter.format(todaysSteps)}걸음을 걸었습니다!",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),

            // UI guide if not authorized
            if (!authorized && errorMsg == null) // Show only if no overriding error
              const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Please grant permissions to view step data."))),

            // Chart and data-related UI (only if authorized)
            if (authorized) ...[
              // Loading indicator specifically for when chart data (barGroups) isn't ready yet
              if (isLoadingData && barGroups.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator(semanticsLabel: 'Loading steps...'))),

              // The Chart
              if (!isLoadingData && barGroups.isNotEmpty)
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.25,
                  child: AspectRatio(
                    aspectRatio: 1.8,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 12, right: 16, left: 6),
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            barGroups: barGroups,
                            maxY: _getChartMaxY(),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: bottomTitles)),
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45, getTitlesWidget: leftTitles)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 5000,
                              getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.5), strokeWidth: 0.4),
                            ),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: Colors.blueGrey,
                                tooltipRoundedRadius: 8,
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  if (group.x < 0 || group.x >= dailySteps.keys.length) return null;
                                  final dateKey = dailySteps.keys.elementAt(group.x);
                                  final date = DateFormat('yyyy-MM-dd').parse(dateKey);
                                  return BarTooltipItem(
                                    '${DateFormat('MMM d').format(date)}\n',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    children: <TextSpan>[
                                      TextSpan(text: (rod.toY.toInt()).toString(), style: const TextStyle(color: Colors.yellow, fontSize: 12, fontWeight: FontWeight.w500)),
                                      const TextSpan(text: ' steps', style: TextStyle(color: Colors.white, fontSize: 12)),
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
                ),
              // Message if no data found after loading
              if (!isLoadingData && dailySteps.isEmpty && barGroups.isEmpty && errorMsg == null)
                const Expanded(child: Center(child: Text("No step data found for the last 7 days.\nPress 'Load/Refresh Steps'.", textAlign: TextAlign.center))),
            ],
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

  @override
  String get pageSpecificFeatureName => "sleep pattern analysis";

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
