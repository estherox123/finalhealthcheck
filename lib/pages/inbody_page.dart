import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/iot/device_control_controller.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';
import '../data/iot/iot_repository.dart';

class InBodyPage extends StatefulWidget {
  const InBodyPage({super.key});

  @override
  State<InBodyPage> createState() => _InBodyPageState();
}

class _InBodyPageState extends State<InBodyPage> {
  late final DeviceControlController _controller;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    try {
      // 1. HA 연결 초기화
      final api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
      final repo = IotRepository(api);
      _controller = DeviceControlController(repo);

      // 2. 리스너 등록 및 데이터 로드
      _controller.addListener(_onUpdate);
      _controller.init();
      setState(() => _isInit = true);
    } catch (e) {
      debugPrint("InBody Controller Init Error: $e");
    }
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_isInit) _controller.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final snap = _controller.snapshot;
    final isLoading = _controller.status == IotStatus.loading;

    // 데이터가 0보다 크면 데이터가 있는 것으로 간주
    final hasData = snap.inbodyWeight > 0;

    // 타임스탬프는 현재 갱신 시점 기준 (HA에 저장된 날짜를 가져오려면 모델에 String 필드 추가 필요)
    final dateStr = hasData
        ? DateFormat('M월 d일 (E) 확인', 'ko').format(DateTime.now())
        : '최근 기록 없음';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // 기존 배경색 유지
      appBar: AppBar(
        title: const Text('체성분 상세 분석', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () => _controller.init(),
            tooltip: '새로고침',
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : !hasData
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: () async => await _controller.init(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 날짜 안내
              Center(
                child: Text(
                  dateStr,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 20),

              // 2. 메인 체중 카드 (기존 디자인 유지)
              _WeightBigCard(weight: snap.inbodyWeight),
              const SizedBox(height: 24),

              // 3. [NEW] 신체 구성 (골격근 vs 체지방량 비교)
              const _SectionTitle('신체 구성'),
              _BodyCompCard(
                muscle: snap.inbodyMuscle,
                fat: snap.inbodyFat,
              ),
              const SizedBox(height: 24),

              // 4. 비만 분석 (체지방률 & BMI)
              const _SectionTitle('비만 분석'),
              _ObesityCard(
                pbf: snap.inbodyPBF,
                bmi: snap.inbodyBMI,
              ),
              const SizedBox(height: 24),

              // 5. 상세 지표 (기초대사량 & 내장지방)
              const _SectionTitle('상세 지표'),
              Row(
                children: [
                  Expanded(
                    child: _DetailSmallCard(
                      label: "기초대사량",
                      value: snap.inbodyBMR.toInt().toString(),
                      unit: "kcal",
                      icon: Icons.local_fire_department,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DetailSmallCard(
                      label: "내장지방",
                      value: "Lv.${snap.inbodyVFL.toInt()}",
                      unit: "",
                      icon: Icons.layers,
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
              ),

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
                    Icon(Icons.cloud_sync, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Home Assistant를 통해 InBody H30NWi 데이터를 실시간으로 동기화합니다.",
                        style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_weight_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("데이터가 없습니다.", style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("인바디 측정 후 새로고침 해주세요.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _controller.init(),
            child: const Text("새로고침"),
          )
        ],
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

// 1. 대형 체중 카드 (기존 디자인 활용)
class _WeightBigCard extends StatelessWidget {
  final double weight;
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
                  weight.toStringAsFixed(1),
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

// 2. 신체 구성 카드 (골격근량 vs 체지방량)
class _BodyCompCard extends StatelessWidget {
  final double muscle;
  final double fat;

  const _BodyCompCard({required this.muscle, required this.fat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          _buildBar("골격근량", muscle, 50.0, Colors.indigoAccent, Icons.fitness_center), // Max 50kg 기준
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _buildBar("체지방량", fat, 50.0, Colors.orangeAccent, Icons.opacity),
        ],
      ),
    );
  }

  Widget _buildBar(String label, double val, double max, Color color, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text("${val.toStringAsFixed(1)} kg", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (val / max).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.grey[100],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}

// 3. 비만 분석 카드 (체지방률 + BMI)
class _ObesityCard extends StatelessWidget {
  final double pbf; // 체지방률
  final double bmi; // BMI

  const _ObesityCard({required this.pbf, required this.bmi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // 체지방률
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("체지방률(PBF)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
              Text("${pbf.toStringAsFixed(1)} %", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (pbf / 50).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey[100],
              color: _getPbfColor(pbf),
            ),
          ),
          const SizedBox(height: 20),

          // BMI
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("체질량지수(BMI)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
              Text("${bmi.toStringAsFixed(1)} kg/m²", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (bmi / 40).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey[100],
              color: _getBmiColor(bmi),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPbfColor(double v) {
    if (v < 10) return Colors.blue;
    if (v < 20) return Colors.green;
    if (v < 28) return Colors.orange;
    return Colors.red;
  }

  Color _getBmiColor(double v) {
    if (v < 18.5) return Colors.blue;
    if (v < 23) return Colors.green;
    if (v < 25) return Colors.orange;
    return Colors.red;
  }
}

// 4. 소형 정보 카드 (Grid용)
class _DetailSmallCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _DetailSmallCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}