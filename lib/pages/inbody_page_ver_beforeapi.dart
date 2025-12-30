// lib/pages/inbody_page.dart
/// LBWeb API 연동하기 전에 사용하던 페이지 (잘 작동하면 없애도 됨)

import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

import 'base_health_page.dart'; // 기존 베이스 페이지 상속

class InBodyPage extends HealthStatefulPage {
  const InBodyPage({super.key});

  @override
  State<InBodyPage> createState() => _InBodyPageState();
}

class _InBodyPageState extends HealthState<InBodyPage> {
  // 헬스 커넥트에서 가져올 데이터 타입 정의
  @override
  List<HealthDataType> get types => const [
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.BASAL_ENERGY_BURNED, // 기초대사량
  ];

  // 데이터 저장 변수
  double? _weight;
  double? _bodyFat; // %
  double? _bmr; // kcal
  DateTime? _lastDate; // 마지막 측정일
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 권한 확인 후 데이터 로드
    authReady.then((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      // 최근 30일 데이터 중 가장 최신 값을 가져옴
      final start = now.subtract(const Duration(days: 30));
      final end = now;

      // 1. 체중
      final weightData = await health.getHealthDataFromTypes(
          types: [HealthDataType.WEIGHT], startTime: start, endTime: end);

      // 2. 체지방률
      final fatData = await health.getHealthDataFromTypes(
          types: [HealthDataType.BODY_FAT_PERCENTAGE], startTime: start, endTime: end);

      // 3. 기초대사량
      final bmrData = await health.getHealthDataFromTypes(
          types: [HealthDataType.BASAL_ENERGY_BURNED], startTime: start, endTime: end);

      // 가장 최신 데이터 추출 (정렬 후 첫 번째)
      // *참고: Health 패키지는 보통 최신순으로 주지 않을 수 있어 정렬 필요
      weightData.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      fatData.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      bmrData.sort((a, b) => b.dateTo.compareTo(a.dateTo));

      setState(() {
        if (weightData.isNotEmpty) {
          _weight = _numVal(weightData.first.value);
          _lastDate = weightData.first.dateTo; // 기준 날짜는 체중으로
        }
        if (fatData.isNotEmpty) _bodyFat = _numVal(fatData.first.value);
        if (bmrData.isNotEmpty) _bmr = _numVal(bmrData.first.value);
      });
    } catch (e) {
      debugPrint("InBody Data Load Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _numVal(dynamic v) {
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _lastDate != null
        ? DateFormat('M월 d일 (E) 측정', 'ko').format(_lastDate!)
        : '최근 기록 없음';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // 통일된 배경색
      appBar: AppBar(
        title: const Text('체성분 분석', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: '새로고침',
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. 상단 날짜 안내
            Center(
              child: Text(
                dateStr,
                style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 20),

            // 2. 체중 카드 (가장 크게)
            _WeightBigCard(weight: _weight),
            const SizedBox(height: 20),

            // 3. 체지방률 (게이지 바)
            _SectionTitle('체지방률'),
            _BodyFatCard(percentage: _bodyFat),
            const SizedBox(height: 20),

            // 4. 기초대사량
            _SectionTitle('기초대사량'),
            _BmrCard(bmr: _bmr),

            const SizedBox(height: 40),

            // 안내 문구
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.grey[600]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "InBody 앱이나 삼성 헬스에서 측정한 데이터가 헬스 커넥트를 통해 자동으로 연동됩니다.",
                      style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------- UI 컴포넌트 ----------------

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
  );
}

// 1. 대형 체중 카드
class _WeightBigCard extends StatelessWidget {
  final double? weight;
  const _WeightBigCard({required this.weight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          const Text('현재 체중', style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                  weight != null ? weight!.toStringAsFixed(1) : '-',
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.0)
              ),
              const SizedBox(width: 8),
              const Text('kg', style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// 2. 체지방률 카드 (게이지 바 포함)
class _BodyFatCard extends StatelessWidget {
  final double? percentage;
  const _BodyFatCard({required this.percentage});

  // 상태 판별 (남녀 평균치를 고려해 대략적인 기준 설정 - 어르신용이라 단순화)
  // 남자 표준: 10~20%, 여자 표준: 18~28% -> 평균적으로 20% 내외를 표준, 30% 이상을 비만으로 단순화
  String _getStatus(double v) {
    if (v < 18) return '표준 이하'; // 근육형 or 마름
    if (v <= 28) return '표준';
    if (v <= 35) return '경도 비만';
    return '비만';
  }

  Color _getColor(double v) {
    if (v < 18) return Colors.blueAccent;
    if (v <= 28) return Colors.green; // 표준
    if (v <= 35) return Colors.orange; // 주의
    return Colors.redAccent; // 위험
  }

  @override
  Widget build(BuildContext context) {
    final hasData = percentage != null;
    final val = percentage ?? 0.0;
    final status = hasData ? _getStatus(val) : '-';
    final color = hasData ? _getColor(val) : Colors.grey;

    // 게이지 비율 (최대 50%로 가정하고 비율 계산)
    final progress = (val / 50.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.water_drop_rounded, color: Colors.indigo, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text("체지방률", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              if (hasData)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(hasData ? val.toStringAsFixed(1) : '-', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
              const Padding(
                padding: EdgeInsets.only(bottom: 6, left: 4),
                child: Text('%', style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 커스텀 게이지 바
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey[100],
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text("0%", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text("25%", style: TextStyle(fontSize: 12, color: Colors.grey)), // 중간값 가이드
              Text("50%+", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}

// 3. 기초대사량 카드
class _BmrCard extends StatelessWidget {
  final double? bmr;
  const _BmrCard({required this.bmr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("기초대사량", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text("숨만 쉬어도 소모되는 에너지", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(bmr != null ? bmr!.round().toString() : '-', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              const Text('kcal', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}