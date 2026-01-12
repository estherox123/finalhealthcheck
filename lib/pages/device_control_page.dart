// lib/pages/device_control_page.dart

import 'package:flutter/material.dart';
import '../data/iot/device_control_controller.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';
import '../data/iot/iot_repository.dart';
import '../data/iot/models.dart';

class DeviceControlPage extends StatefulWidget {
  const DeviceControlPage({super.key});
  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  late final DeviceControlController _c;

  @override
  void initState() {
    super.initState();
    try {
      final api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
      final repo = IotRepository(api);
      _c = DeviceControlController(repo);
      _c.addListener(() { if (mounted) setState(() {}); });
      _c.init();
    } catch (e) {
      debugPrint("IoT Controller Init Error: $e");
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _c.snapshot;
    final loading = _c.status != IotStatus.ready;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('기기 제어', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _c.init(),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _c.init(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // 1. 거실 에어컨 섹션
            _SectionTitle('거실 에어컨'),
            _AirconCard(
              location: AcLocation.living, // 위치 지정
              state: snap.livingAc,        // 거실 상태 주입
              controller: _c,
              loading: loading,
            ),

            const SizedBox(height: 32),

            // 2. 안방 에어컨 섹션
            _SectionTitle('안방 에어컨'),
            _AirconCard(
              location: AcLocation.bedroom, // 위치 지정
              state: snap.bedroomAc,        // 안방 상태 주입
              controller: _c,
              loading: loading,
            ),

            const SizedBox(height: 32),

            // 3. 환기 섹션 (리모컨 허브 보류, 전원만 표시)
            _SectionTitle('실내 환기'),
            _AirpassCard(
              isOn: snap.hrv.isOn,
              onToggle: _c.toggleHrv,
              loading: loading,
            ),

            // 조명, 블라인드는 삭제됨
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
    ),
  );
}

// ================================ [1] 공용 에어컨 카드 ================================
class _AirconCard extends StatelessWidget {
  final AcLocation location; // 어느 방인지 구분
  final AirconState state;
  final DeviceControlController controller;
  final bool loading;

  const _AirconCard({
    required this.location,
    required this.state,
    required this.controller,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn;

    // 모드에 따른 UI 색상 가져오기
    final bgColor = controller.getUiColor(state.mode);
    final activeColor = controller.getActiveColor(state.mode);

    return Container(
      decoration: BoxDecoration(
        color: on ? bgColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          // 상단: 상태 및 전원 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(on ? state.mode.label : '전원 꺼짐', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: on ? Colors.black87 : Colors.grey)),
                      const SizedBox(height: 4),
                      // 꺼져있어도 실내 온도는 보여줌
                      Text("현재 실내 ${state.currentTemperature}°C", style: const TextStyle(fontSize: 13, color: Colors.grey))
                    ]
                ),
                _PowerButton(
                    on: on,
                    onPressed: loading ? null : () => controller.toggleAc(location) // 위치 정보 전달
                ),
              ],
            ),
          ),

          if (on) ...[
            // 켜졌을 때: 온도 조절 슬라이더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(children: [
                Text("희망 온도", style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text("${state.temperature}°C", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300, color: Colors.black87, letterSpacing: -1.5)),
                const SizedBox(height: 10),
                SliderTheme(
                  data: SliderThemeData(trackHeight: 6, activeTrackColor: activeColor, inactiveTrackColor: activeColor.withOpacity(0.2), thumbColor: activeColor, overlayColor: activeColor.withOpacity(0.1), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)),
                  child: Slider(
                      value: state.temperature.toDouble(),
                      min: 18,
                      max: 30,
                      divisions: 12,
                      onChanged: loading ? null : (val) => controller.setTargetTemperature(location, val)
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),

            // 모드 & 바람세기 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: _ControlBox(title: "운전 모드", icon: _getModeIcon(state.mode), value: state.mode.label, color: Colors.white, onTap: () => _showModePicker(context))),
                const SizedBox(width: 12),
                Expanded(child: _ControlBox(title: "바람 세기", icon: Icons.wind_power, value: _fanSpeedToString(state.fanSpeed), color: Colors.white, onTap: () => _showFanSpeedPicker(context))),
              ]),
            ),

            // 타이머 예약
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.bedtime_outlined, color: Colors.orangeAccent),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("취침 예약", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  if (state.timerHours > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)), child: Text("${state.timerHours}시간 후 꺼짐", style: const TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _SleepTimerBtn(label: "해제", selected: state.timerHours == 0, onTap: () => controller.setAcTimer(location, 0)),
                  _SleepTimerBtn(label: "1시간", selected: state.timerHours == 1, onTap: () => controller.setAcTimer(location, 1)),
                  _SleepTimerBtn(label: "2시간", selected: state.timerHours == 2, onTap: () => controller.setAcTimer(location, 2)),
                  _SleepTimerBtn(label: "4시간", selected: state.timerHours == 4, onTap: () => controller.setAcTimer(location, 4)),
                ])
              ]),
            ),
            const SizedBox(height: 10),
          ] else ...[
            // 꺼졌을 때: 큼지막한 아이콘
            const SizedBox(height: 30),
            Center(child: Icon(Icons.ac_unit, size: 80, color: Colors.grey.withOpacity(0.2))),
            const SizedBox(height: 40),
          ]
        ],
      ),
    );
  }

  // Enum 확장 (Extension) 대신 함수로 간단 구현
  String getModeLabel(AcMode m) {
    switch (m) { case AcMode.cool: return '냉방'; case AcMode.heat: return '난방'; case AcMode.dry: return '제습'; case AcMode.fan: return '송풍'; case AcMode.auto: return '자동'; }
  }

  IconData _getModeIcon(AcMode m) {
    switch (m) { case AcMode.cool: return Icons.ac_unit; case AcMode.heat: return Icons.wb_sunny; case AcMode.dry: return Icons.water_drop; case AcMode.fan: return Icons.air; case AcMode.auto: return Icons.hdr_auto; }
  }

  String _fanSpeedToString(AcFanSpeed s) {
    switch (s) { case AcFanSpeed.auto: return '자동'; case AcFanSpeed.low: return '약풍'; case AcFanSpeed.medium: return '중풍'; case AcFanSpeed.high: return '강풍'; }
  }

  void _showModePicker(BuildContext context) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => Container(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("운전 모드 선택", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Wrap(
                      spacing: 12, runSpacing: 12,
                      children: AcMode.values.map((m) => _OptionChip(
                          label: getModeLabel(m),
                          selected: state.mode == m,
                          onSelected: () { controller.setAcMode(location, m); Navigator.pop(context); }
                      )).toList()
                  )
                ]
            )
        )
    );
  }

  void _showFanSpeedPicker(BuildContext context) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => Container(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("바람 세기 선택", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Wrap(
                      spacing: 12, runSpacing: 12,
                      children: AcFanSpeed.values.map((s) => _OptionChip(
                          label: _fanSpeedToString(s),
                          selected: state.fanSpeed == s,
                          onSelected: () { controller.setAcFanSpeed(location, s); Navigator.pop(context); }
                      )).toList()
                  )
                ]
            )
        )
    );
  }
}


// ================================ [2] 환기 카드 (유지) ================================
class _AirpassCard extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggle;
  final bool loading;
  const _AirpassCard({required this.isOn, required this.onToggle, required this.loading});

  @override
  Widget build(BuildContext context) {
    final bgColor = isOn ? const Color(0xFFE0F2F1) : Colors.white;
    final fgColor = isOn ? Colors.teal : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.air_rounded, color: fgColor, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('환기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text(isOn ? "가동 중" : "꺼짐", style: TextStyle(fontSize: 13, color: isOn ? Colors.teal : Colors.grey)),
                    ],
                  ),
                ],
              ),
              _PowerButton(on: isOn, onPressed: loading ? null : onToggle),
            ],
          ),
          if (isOn) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(16)),
              child: const Text("신선한 공기 순환 중 🍃", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.teal)),
            ),
          ]
        ],
      ),
    );
  }
}

// ---------------------- 공통 위젯들 (그대로 사용) ----------------------
class _PowerButton extends StatelessWidget {
  final bool on;
  final VoidCallback? onPressed;
  const _PowerButton({required this.on, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]),
      child: IconButton(icon: const Icon(Icons.power_settings_new), iconSize: 28, color: on ? Colors.blue : Colors.grey, onPressed: onPressed),
    );
  }
}

class _ControlBox extends StatelessWidget {
  final String title; final IconData icon; final String value; final Color color; final VoidCallback onTap;
  const _ControlBox({required this.title, required this.icon, required this.value, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: Colors.grey[700], size: 24), Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[300])]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])), const SizedBox(height: 2), Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87))])
        ]),
      ),
    );
  }
}

class _SleepTimerBtn extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _SleepTimerBtn({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: selected ? Colors.black87 : Colors.grey[100], borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.grey[600])),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onSelected;
  const _OptionChip({required this.label, required this.selected, required this.onSelected});
  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label), selected: selected, onSelected: (_) => onSelected(),
      selectedColor: Colors.black87, labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
      backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: selected ? Colors.transparent : Colors.grey.shade300)),
    );
  }
}