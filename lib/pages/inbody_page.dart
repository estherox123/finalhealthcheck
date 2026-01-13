import 'package:flutter/material.dart';
import 'package:external_app_launcher/external_app_launcher.dart';
import 'dart:io' show Platform;

import '../data/iot/device_control_controller.dart';
import '../data/iot/iot_repository.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';

class InBodyPage extends StatefulWidget {
  const InBodyPage({super.key});

  @override
  State<InBodyPage> createState() => _InBodyPageState();
}

class _InBodyPageState extends State<InBodyPage> {
  late final DeviceControlController _iotDc;

  @override
  void initState() {
    super.initState();
    final api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    _iotDc = DeviceControlController(IotRepository(api));
    _iotDc.addListener(_onRefresh);
    _iotDc.init();
  }

  void _onRefresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _iotDc.removeListener(_onRefresh);
    super.dispose();
  }

  Future<void> _launchInBodyApp() async {
    await LaunchApp.openApp(
      androidPackageName: 'com.inbody2014.inbody',
      iosUrlScheme: 'inbody://',
      appStoreLink: 'https://apps.apple.com/kr/app/inbody/id884923678',
      openStore: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _iotDc.snapshot;

    final double weight = snap.inbodyWeight;
    final double muscle = snap.inbodyMuscle;
    final double fat = snap.inbodyFat;
    final double bmi = snap.inbodyBMI;
    final double pbf = snap.inbodyPBF;
    final double bmr = snap.inbodyBMR;
    final double vfl = snap.inbodyVFL;

    return Scaffold(
      // 배경색을 테마에 맡기지 않고 명시적으로 설정 (미러에서 진입 시 자동 검정 처리됨)
      // 단, AppBar는 항상 밝은 테마 느낌을 유지하려면 아래처럼 설정
      appBar: AppBar(
        title: const Text("체성분 분석", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF0F2F5), // 미러모드에선 이 색이 무시되고 검정이 될 수 있음
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(onPressed: _iotDc.init, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _iotDc.init(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. 메인 체중 카드
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  const Text("현재 체중", style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        weight > 0 ? weight.toStringAsFixed(1) : "-",
                        // ✅ 여기는 이미 검은색으로 잘 되어 있음
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                      const SizedBox(width: 4),
                      const Text("kg", style: TextStyle(fontSize: 20, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _MainSummaryItem(label: "골격근량", value: muscle, unit: "kg", icon: Icons.fitness_center, color: Colors.blueAccent),
                      Container(width: 1, height: 40, color: Colors.grey[200]),
                      _MainSummaryItem(label: "체지방량", value: fat, unit: "kg", icon: Icons.opacity, color: Colors.orangeAccent),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. 상세 지표 그리드
            // ✅ 여기도 텍스트 색상을 검정으로 강제해야 함 (아래 _DetailCard 수정됨)
            // 미러 모드(다크테마)에서는 기본 텍스트가 흰색이라 흰 배경 위에서 안 보였던 것
            Text("상세 지표", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _DetailCard(title: "BMI", value: bmi, unit: "kg/m²", isNormal: bmi >= 18.5 && bmi <= 23),
                _DetailCard(title: "체지방률", value: pbf, unit: "%", isNormal: pbf >= 10 && pbf <= 20),
                _DetailCard(title: "기초대사량", value: bmr, unit: "kcal", isNormal: true),
                _DetailCard(title: "내장지방", value: vfl, unit: "Lv", isNormal: vfl <= 9),
              ],
            ),
            const SizedBox(height: 30),

            // 3. 인바디 앱 바로가기 버튼
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _launchInBodyApp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCA202D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text("InBody 앱 열기", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            const Center(child: Text("그래프 및 변화 분석은 공식 앱을 이용하세요.", style: TextStyle(fontSize: 12, color: Colors.grey))),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _MainSummaryItem extends StatelessWidget {
  final String label; final double value; final String unit; final IconData icon; final Color color;
  const _MainSummaryItem({required this.label, required this.value, required this.unit, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14))]),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // ✅ [수정] color: Colors.black87 추가 -> 흰 배경 위에서 무조건 검정색 유지
            Text(value > 0 ? value.toStringAsFixed(1) : "-", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(width: 2),
            Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        )
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title; final double value; final String unit; final bool isNormal;
  const _DetailCard({required this.title, required this.value, required this.unit, required this.isNormal});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.bold)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  // ✅ [수정] color: Colors.black87 추가 -> 미러 모드(다크테마)에서도 검정색으로 보이게 함
                  Text(value > 0 ? value.toStringAsFixed(1) : "-", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black87)),
                  const SizedBox(width: 2),
                  Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              if (value > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isNormal ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(isNormal ? "정상" : "주의", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isNormal ? Colors.green : Colors.orange)),
                )
            ],
          )
        ],
      ),
    );
  }
}