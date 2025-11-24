import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';

import 'base_health_page.dart';

class SleepDetailPage extends HealthStatefulPage {
  const SleepDetailPage({super.key});

  @override
  State<SleepDetailPage> createState() => _SleepDetailPageState();
}

class _SleepDetailPageState extends HealthState<SleepDetailPage> {
  // 이 페이지에서 사용할 타입들
  @override
  List<HealthDataType> get types => const [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    // 아래 4개는 버전에 따라 이름이 다를 수 있음 → 현재 잘 동작하던 값 그대로 맞춰 쓰면 됨
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
  ];

  bool _loading = true;
  String? _localError;
  _SleepVm? _vm;

  @override
  void initState() {
    super.initState();
    authReady.then((_) {
      if (!mounted) return;
      _load();
    });
  }

  // ---------------- 공통 헬퍼 ----------------

  double? _numVal(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) {
      final n = v.numericValue;
      return n == null ? null : n.toDouble();
    }
    try {
      final any = (v as dynamic).numericValue;
      if (any is num) return any.toDouble();
    } catch (_) {}
    return null;
  }

  Duration _clampedDuration(
      DateTime? from, DateTime? to, DateTime winStart, DateTime winEnd) {
    if (from == null || to == null) return Duration.zero;
    final s = from.isBefore(winStart) ? winStart : from;
    final e = to.isAfter(winEnd) ? winEnd : to;
    if (!e.isAfter(s)) return Duration.zero;
    return e.difference(s);
  }

  // ---------------- 데이터 로딩 ----------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _localError = null;
      _vm = null;
    });

    try {
      if (!authorized) {
        _localError = '헬스 데이터 권한이 없어 수면 정보를 불러올 수 없습니다.';
        return;
      }

      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);

      // "지난 밤" 윈도우: 어제 18:00 ~ 오늘 12:00
      final winAnchor = today0;
      final winStart = winAnchor.subtract(const Duration(hours: 6));
      final winEnd = winAnchor.add(const Duration(hours: 12));

      // 1) 지난 밤 수면 단계/타임라인
      final stageTypes = <HealthDataType>[
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
      ];

      final stagePoints = await health.getHealthDataFromTypes(
        types: stageTypes,
        startTime: winStart,
        endTime: winEnd,
      );

      // 단계별 duration/segment 계산
      final stageDurations = <SleepStageType, Duration>{
        SleepStageType.deep: Duration.zero,
        SleepStageType.light: Duration.zero,
        SleepStageType.rem: Duration.zero,
        SleepStageType.wake: Duration.zero,
      };
      final segments = <SleepStageSegment>[];

      SleepStageType? _mapType(HealthDataType t) {
        switch (t) {
          case HealthDataType.SLEEP_DEEP:
            return SleepStageType.deep;
          case HealthDataType.SLEEP_LIGHT:
            return SleepStageType.light;
          case HealthDataType.SLEEP_REM:
            return SleepStageType.rem;
          case HealthDataType.SLEEP_AWAKE:
            return SleepStageType.wake;
          default:
            return null;
        }
      }

      for (final p in stagePoints) {
        final stg = _mapType(p.type);
        if (stg == null) continue;
        final dur = _clampedDuration(p.dateFrom, p.dateTo, winStart, winEnd);
        if (dur <= Duration.zero) continue;

        stageDurations[stg] = stageDurations[stg]! + dur;
        segments.add(SleepStageSegment(
          start: p.dateFrom!.isBefore(winStart) ? winStart : p.dateFrom!,
          end: p.dateTo!.isAfter(winEnd) ? winEnd : p.dateTo!,
          stage: stg,
        ));
      }

      // 총 수면 시간: 기본은 단계 기반(깊은/얕은/렘), 없으면 SLEEP_SESSION으로 fallback
      Duration totalAsleep = stageDurations[SleepStageType.deep]! +
          stageDurations[SleepStageType.light]! +
          stageDurations[SleepStageType.rem]!;
      Duration totalWake = stageDurations[SleepStageType.wake]!;

      final hasStageAsleep = totalAsleep.inMinutes > 0;

      if (!hasStageAsleep) {
        // 워치를 차지 않았거나 수면 단계가 없는 날:
        // SLEEP_SESSION 기반으로라도 지난 밤 수면 시간을 보여주기
        final sessions = await health.getHealthDataFromTypes(
          types: const [HealthDataType.SLEEP_SESSION],
          startTime: winStart,
          endTime: winEnd,
        );

        Duration sessTotal = Duration.zero;
        for (final p in sessions) {
          sessTotal += _clampedDuration(p.dateFrom, p.dateTo, winStart, winEnd);
        }

        if (sessTotal.inMinutes > 0) {
          totalAsleep = sessTotal;
          totalWake = Duration.zero;
        }
      }

      // 2) 최근 7일 수면 (우선 수면 단계 기반, 없으면 SLEEP_SESSION 기반 fallback)
      final last7 = <DateTime, Duration>{};

      for (int i = 6; i >= 0; i--) {
        final anchor = today0.subtract(Duration(days: i));
        final s = anchor.subtract(const Duration(hours: 6));
        final e = anchor.add(const Duration(hours: 12));

        Duration sleepSum = Duration.zero;

        // 2-1) 우선 수면 단계(DEEP/LIGHT/REM) 합산 시도
        final stagePts = await health.getHealthDataFromTypes(
          types: stageTypes,
          startTime: s,
          endTime: e,
        );

        for (final p in stagePts) {
          final stg = _mapType(p.type);
          if (stg == null || stg == SleepStageType.wake) continue;
          sleepSum += _clampedDuration(p.dateFrom, p.dateTo, s, e);
        }

        final hasStageSleep = sleepSum.inMinutes > 0;

        // 2-2) 단계 데이터가 전혀 없으면 SLEEP_SESSION 기반 fallback
        if (!hasStageSleep) {
          final sessions = await health.getHealthDataFromTypes(
            types: const [HealthDataType.SLEEP_SESSION],
            startTime: s,
            endTime: e,
          );
          for (final p in sessions) {
            sleepSum += _clampedDuration(p.dateFrom, p.dateTo, s, e);
          }
        }

        last7[anchor] = sleepSum;
      }

      _vm = _SleepVm(
        nightStart: winStart,
        nightEnd: winEnd,
        totalAsleep: totalAsleep,
        totalWake: totalWake,
        stageDurations: stageDurations,
        segments: segments..sort((a, b) => a.start.compareTo(b.start)),
        last7Nights: last7,
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('Sleep load error: $e\n$st');
      _localError = '수면 데이터를 불러오는 중 오류가 발생했습니다.';
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: const Text('수면 요약'),
    );

    if (_loading) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMsg != null || _localError != null) {
      return Scaffold(
        appBar: appBar,
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                errorMsg ?? _localError ?? '알 수 없는 오류',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final vm = _vm;
    if (vm == null) {
      return Scaffold(
        appBar: appBar,
        body: RefreshIndicator(
          onRefresh: _load,
          child: const Center(
            child: Text('수면 데이터를 찾을 수 없습니다.'),
          ),
        ),
      );
    }

    final df = DateFormat('M/d');
    final nightLabel = '${df.format(vm.nightStart)} 기준';

    return Scaffold(
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  errorMsg!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            // -------- 설명 + 새로고침 --------
            Text(
              '워치로 기록된 수면 단계를 바탕으로\n'
                  '지난 밤의 수면 시간과 패턴을 간단히 요약해줍니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('불러오기/새로고침'),
              ),
            ),
            const SizedBox(height: 16),

            // -------- 지난 밤 수면 시간 카드 --------
            _LastNightSummaryCard(vm: vm, nightLabel: nightLabel),
            const SizedBox(height: 20),

            // -------- 지난 밤 수면 단계 텍스트 + 비율 바 --------
            _SleepStageSummary(vm: vm),
            const SizedBox(height: 20),

            // -------- 수면 단계 타임라인 --------
            SleepStageTimeline(segments: vm.segments),
            const SizedBox(height: 40),

            // -------- 최근 7일 수면 막대 그래프 --------
            Text(
              '최근 7일 수면 시간',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '막대를 누르면 날짜별 수면 시간을 볼 수 있습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            _Last7DaysChart(vm: vm),
            const SizedBox(height: 24),

            Text(
              '표시되는 수면 시간은 가능한 경우 깊은/얕은/렘 수면을 합산한 값이며, '
                  '워치 수면 단계가 없는 날에는 기록된 총 수면시간이 표시됩니다.\n'
                  '이 정보는 의료적 판단을 대체하지 않으니 이상 증상이 느껴지면 '
                  '반드시 의료진과 상의하세요.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- ViewModel ----------------

class _SleepVm {
  final DateTime nightStart;
  final DateTime nightEnd;
  final Duration totalAsleep;
  final Duration totalWake;
  final Map<SleepStageType, Duration> stageDurations;
  final List<SleepStageSegment> segments;
  final Map<DateTime, Duration> last7Nights;

  const _SleepVm({
    required this.nightStart,
    required this.nightEnd,
    required this.totalAsleep,
    required this.totalWake,
    required this.stageDurations,
    required this.segments,
    required this.last7Nights,
  });
}

// ---------------- 수면 단계 타입/세그먼트 ----------------

enum SleepStageType { wake, light, deep, rem }

class SleepStageSegment {
  final DateTime start;
  final DateTime end;
  final SleepStageType stage;

  SleepStageSegment({
    required this.start,
    required this.end,
    required this.stage,
  });
}

String stageLabel(SleepStageType t) {
  switch (t) {
    case SleepStageType.deep:
      return '깊은 수면';
    case SleepStageType.light:
      return '얕은 수면';
    case SleepStageType.rem:
      return '렘 수면';
    case SleepStageType.wake:
      return '깬 상태';
  }
}

Color stageColor(SleepStageType t) {
  switch (t) {
    case SleepStageType.deep:
      return const Color(0xFF1E3A8A); // 남색
    case SleepStageType.light:
      return const Color(0xFF3B82F6); // 파랑
    case SleepStageType.rem:
      return const Color(0xFF38BDF8); // 밝은 파랑
    case SleepStageType.wake:
      return const Color(0xFFF97316); // 주황
  }
}

// ---------------- 위젯: 지난 밤 수면 요약 카드 ----------------

class _LastNightSummaryCard extends StatelessWidget {
  final _SleepVm vm;
  final String nightLabel;

  const _LastNightSummaryCard({
    required this.vm,
    required this.nightLabel,
  });

  String _fmtDuration(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return '${h}시간 ${m}분';
  }

  @override
  Widget build(BuildContext context) {
    final totalSleep = vm.totalAsleep;
    final totalInBed = vm.totalAsleep + vm.totalWake;

    final hasSleep = totalSleep.inMinutes > 0;
    final hasInBed = totalInBed.inMinutes > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.indigo.withOpacity(0.18),
            child: const Icon(Icons.bedtime, color: Colors.indigo, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 타이틀
                Text(
                  '지난 밤 수면 시간',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),

                // 지난 밤 수면 시간 (깨어있지 않은 시간)
                Text(
                  hasSleep ? _fmtDuration(totalSleep) : '기록 없음',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.indigo[700],
                  ),
                ),
                const SizedBox(height: 4),

                // 침대에 머문 시간 (수면 + 깬 시간)
                Text(
                  hasInBed
                      ? '침대에 머문 시간: ${_fmtDuration(totalInBed)}'
                      : '침대에 머문 시간: -',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),

                // 기준 날짜 (가장 작게)
                Text(
                  nightLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 위젯: 수면 단계 요약 + 비율 바 ----------------

class _SleepStageSummary extends StatelessWidget {
  final _SleepVm vm;

  const _SleepStageSummary({required this.vm});

  String _fmt(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return '${h}시간 ${m}분';
  }

  @override
  Widget build(BuildContext context) {
    final deep = vm.stageDurations[SleepStageType.deep] ?? Duration.zero;
    final light = vm.stageDurations[SleepStageType.light] ?? Duration.zero;
    final rem = vm.stageDurations[SleepStageType.rem] ?? Duration.zero;
    final wake = vm.stageDurations[SleepStageType.wake] ?? Duration.zero;

    // "실제 수면 단계" 데이터 존재 여부 (깊은/얕은/렘 중 하나라도 있으면 true)
    final hasSleepStage =
        deep.inMinutes > 0 || light.inMinutes > 0 || rem.inMinutes > 0;

    // 워치 수면 단계가 전혀 없는 날 → 안내 문구만 보여주기
    if (!hasSleepStage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '지난 밤 수면 단계',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '워치에서 수면 단계를 기록하지 않아\n'
                '단계별 정보는 표시되지 않습니다.\n'
                '그래도 전체 수면 시간은 위 카드와 아래 그래프에 반영되어 있습니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[700],
            ),
          ),
        ],
      );
    }

    // 여기부터는 "워치 단계 데이터가 있는 날"에만 실행
    final total = deep + light + rem + wake;
    final asleepTotal = deep + light + rem;

    double pct(Duration d) =>
        total.inMinutes == 0 ? 0 : d.inMinutes * 100 / total.inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '지난 밤 수면 단계',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _stageRow('깊은 수면', deep, pct(deep), context),
              _stageRow('렘 수면', rem, pct(rem), context),
              _stageRow('얕은 수면', light, pct(light), context),
              const Divider(height: 16),
              _stageRow('깬 상태', wake, pct(wake), context),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '총 수면(깨어있지 않은 시간): ${_fmt(asleepTotal)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _StageRatioBar(vm: vm),
      ],
    );
  }

  Widget _stageRow(
      String label, Duration d, double percent, BuildContext context) {
    final hasData = d.inMinutes > 0;
    final txt = hasData ? _fmt(d) : '-';
    final pctText = hasData ? '${percent.toStringAsFixed(0)}%' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            txt,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              pctText,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageRatioBar extends StatelessWidget {
  final _SleepVm vm;

  const _StageRatioBar({required this.vm});

  @override
  Widget build(BuildContext context) {
    final deep = vm.stageDurations[SleepStageType.deep] ?? Duration.zero;
    final light = vm.stageDurations[SleepStageType.light] ?? Duration.zero;
    final rem = vm.stageDurations[SleepStageType.rem] ?? Duration.zero;
    final wake = vm.stageDurations[SleepStageType.wake] ?? Duration.zero;

    final totals = {
      SleepStageType.deep: deep,
      SleepStageType.rem: rem,
      SleepStageType.light: light,
      SleepStageType.wake: wake,
    };

    final totalMinutes =
    totals.values.fold<int>(0, (sum, d) => sum + d.inMinutes);

    if (totalMinutes == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Row(
            children: [
              for (final entry in totals.entries)
                if (entry.value.inMinutes > 0)
                  Expanded(
                    flex: entry.value.inMinutes,
                    child: Container(
                      height: 12,
                      color: stageColor(entry.key),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in totals.entries)
              if (entry.value.inMinutes > 0)
                _LegendChip(
                  color: stageColor(entry.key),
                  label: stageLabel(entry.key),
                ),
          ],
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------- 수면 단계 타임라인 ----------------

class SleepStageTimeline extends StatefulWidget {
  final List<SleepStageSegment> segments;
  final int minSegmentMinutes;

  const SleepStageTimeline({
    super.key,
    required this.segments,
    this.minSegmentMinutes = 3,
  });

  @override
  State<SleepStageTimeline> createState() => _SleepStageTimelineState();
}

class _SleepStageTimelineState extends State<SleepStageTimeline> {
  SleepStageSegment? _selectedSeg;
  double? _touchRatio; // 0~1: 타임라인 내 상대 위치

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) {
      return const Text('수면 단계 기록이 없습니다.');
    }

    final sorted = [...widget.segments]
      ..sort((a, b) => a.start.compareTo(b.start));
    final cleaned = _normalizeSegments(
      sorted,
      minMinutes: widget.minSegmentMinutes,
    );

    if (cleaned.isEmpty) {
      return const Text('수면 단계 기록이 없습니다.');
    }

    final start = cleaned.first.start;
    final end = cleaned.last.end;
    final totalMinutesRaw = end.difference(start).inMinutes;
    final totalMinutes = totalMinutesRaw <= 0 ? 1 : totalMinutesRaw;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '수면 단계 (타임라인)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '아래로 내려갈수록 더 깊은 수면 단계입니다. 선을 눌러 구간별 단계를 볼 수 있어요.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            // 좌우 padding 8씩 포함된 컨테이너 안의 실제 타임라인 폭
            final timelineWidth = constraints.maxWidth - 16;

            void handleTouch(Offset localPos) {
              // localPos는 타임라인 영역(패딩 포함 안 한 내부) 기준
              final dx = localPos.dx.clamp(0, timelineWidth);
              final ratio = timelineWidth <= 0 ? 0.0 : dx / timelineWidth;
              final minutesFromStart = (totalMinutes * ratio).round();
              final t = start.add(Duration(minutes: minutesFromStart));

              SleepStageSegment? found;
              for (final seg in cleaned) {
                if (!t.isBefore(seg.start) && t.isBefore(seg.end)) {
                  found = seg;
                  break;
                }
              }

              setState(() {
                _touchRatio = ratio;
                _selectedSeg = found;
              });
            }

            return SizedBox(
              height: 150,
              child: Stack(
                children: [
                  // 배경 + 타임라인
                  Positioned.fill(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                        8,
                        42,
                        8,
                        8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) =>
                                  handleTouch(details.localPosition),
                              onPanDown: (details) =>
                                  handleTouch(details.localPosition),
                              onPanUpdate: (details) =>
                                  handleTouch(details.localPosition),
                              child: CustomPaint(
                                painter: _SleepStagePainter(
                                  segments: cleaned,
                                  rangeStart: start,
                                  rangeEnd: end,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _TimelineLabels(start: start, end: end),
                        ],
                      ),
                    ),
                  ),

                  // 터치 툴팁 오버레이
                  if (_selectedSeg != null && _touchRatio != null)
                    Positioned(
                      top: 2, // 툴팁 위치 조정 (작을수록 위로)
                      left: () {
                        // 타임라인 안에서의 중앙 X좌표 (좌측 padding 8 포함)
                        final centerX = 8 + timelineWidth * _touchRatio!;
                        const tooltipWidth = 160.0;
                        final half = tooltipWidth / 2;
                        double left = centerX - half;

                        // 좌우 화면 밖으로 삐져나가지 않게 클램핑
                        if (left < 4) left = 4;
                        if (left + tooltipWidth > constraints.maxWidth - 4) {
                          left = constraints.maxWidth - tooltipWidth - 4;
                        }
                        return left;
                      }(),
                      child: _SegmentTooltip(seg: _selectedSeg!),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  List<SleepStageSegment> _normalizeSegments(
      List<SleepStageSegment> input, {
        required int minMinutes,
      }) {
    if (input.isEmpty) return const [];
    final result = <SleepStageSegment>[];

    SleepStageSegment? buffer;

    void flushBuffer() {
      if (buffer != null) result.add(buffer!);
      buffer = null;
    }

    for (final seg in input) {
      final minutes = seg.end.difference(seg.start).inMinutes;
      if (buffer == null) {
        buffer = seg;
        continue;
      }

      final gap = seg.start.difference(buffer!.end).inMinutes;
      final sameStage = seg.stage == buffer!.stage;

      if (sameStage && gap <= 1) {
        buffer = SleepStageSegment(
          start: buffer!.start,
          end: seg.end,
          stage: buffer!.stage,
        );
        continue;
      }

      if (minutes < minMinutes) {
        // 짧은 조각: 앞 세그먼트에 흡수
        buffer = SleepStageSegment(
          start: buffer!.start,
          end: seg.end,
          stage: buffer!.stage,
        );
        continue;
      }

      flushBuffer();
      buffer = seg;
    }

    flushBuffer();
    return result;
  }
}

class _SegmentTooltip extends StatelessWidget {
  final SleepStageSegment seg;

  const _SegmentTooltip({required this.seg});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('HH:mm');

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stageLabel(seg.stage),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${df.format(seg.start)} ~ ${df.format(seg.end)}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepStagePainter extends CustomPainter {
  final List<SleepStageSegment> segments;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  _SleepStagePainter({
    required this.segments,
    required this.rangeStart,
    required this.rangeEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final totalMinutes =
    rangeEnd.difference(rangeStart).inMinutes.clamp(1, 24 * 60);
    final height = size.height;
    final width = size.width;

    double yForStage(SleepStageType stage) {
      switch (stage) {
        case SleepStageType.deep:
          return height * 0.8;
        case SleepStageType.light:
          return height * 0.55;
        case SleepStageType.rem:
          return height * 0.3;
        case SleepStageType.wake:
          return height * 0.1;
      }
    }

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 0.7;

    for (final stage in SleepStageType.values) {
      final y = yForStage(stage);
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    Offset? prev;

    for (final seg in segments) {
      final startMin = seg.start.difference(rangeStart).inMinutes;
      final endMin = seg.end.difference(rangeStart).inMinutes;
      final x0 = (startMin / totalMinutes) * width;
      final x1 = (endMin / totalMinutes) * width;
      final y = yForStage(seg.stage);

      final paint = Paint()
        ..color = stageColor(seg.stage)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.square;

      canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);

      if (prev != null && prev!.dy != y) {
        final connectorPaint = Paint()
          ..color = stageColor(seg.stage)
          ..strokeWidth = 4;
        canvas.drawLine(prev!, Offset(x0, y), connectorPaint);
      }

      prev = Offset(x1, y);
    }
  }

  @override
  bool shouldRepaint(covariant _SleepStagePainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd;
  }
}

class _TimelineLabels extends StatelessWidget {
  final DateTime start;
  final DateTime end;

  const _TimelineLabels({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('HH:mm');
    final mid = start.add(end.difference(start) ~/ 2);

    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.grey[700],
      fontSize: 11,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(df.format(start), style: style),
        Text(df.format(mid), style: style),
        Text(df.format(end), style: style),
      ],
    );
  }
}

class _SelectedSegmentLabel extends StatelessWidget {
  final SleepStageSegment seg;

  const _SelectedSegmentLabel({required this.seg});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('HH:mm');
    final text =
        '${df.format(seg.start)} ~ ${df.format(seg.end)}  ${stageLabel(seg.stage)}';

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.grey[800],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------- 최근 7일 막대 그래프 ----------------

class _Last7DaysChart extends StatelessWidget {
  final _SleepVm vm;

  const _Last7DaysChart({required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.last7Nights.isEmpty) {
      return const Text('최근 7일 수면 데이터가 없습니다.');
    }

    final entries = vm.last7Nights.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final groups = <BarChartGroupData>[];
    final labels = <String>[];

    final koreanDays = ['월', '화', '수', '목', '금', '토', '일'];

    double maxHours = 0;

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final hours = e.value.inMinutes / 60.0;
      maxHours = hours > maxHours ? hours : maxHours;

      final isToday = e.key.year == todayDate.year &&
          e.key.month == todayDate.month &&
          e.key.day == todayDate.day;

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: hours,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              color: isToday
                  ? Colors.indigo
                  : Colors.indigo.withOpacity(0.65), // 오늘 막대만 진하게
            ),
          ],
        ),
      );

      labels.add(koreanDays[e.key.weekday - 1]);
    }

    final maxY = (maxHours == 0 ? 5.0 : (maxHours * 1.2)).ceilToDouble();

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          barGroups: groups,
          maxY: maxY,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 2,
          ),
          titlesData: FlTitlesData(
            topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      labels[i],
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == meta.max || value == meta.min) {
                    return const SizedBox.shrink();
                  }
                  if (value % 2 != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      '${value.toInt()}시간',
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x.toInt();
                if (idx < 0 || idx >= entries.length) return null;
                final date = entries[idx].key;
                final hours = rod.toY;
                return BarTooltipItem(
                  '${date.month}/${date.day}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: hours.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: '시간',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
