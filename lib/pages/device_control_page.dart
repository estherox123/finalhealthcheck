// lib/pages/device_control_page.dart

import 'package:flutter/material.dart';
import '../data/iot/device_control_controller.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';
import '../data/iot/iot_api.dart';
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
    _c = DeviceControlController(IotRepository(_createApi()));
    _c.addListener(() => setState(() {}));
    _c.init();
  }

  IotApi _createApi() {
    final opts = HomeAssistantOptions.fromEnv();
    if (!opts.isConfigured) {
      throw StateError(
        'Home Assistant 연동 정보가 없습니다. flutter run 시 환경변수를 설정하세요.',
      );
    }
    return HomeAssistantApi(options: opts);
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
      ),
      body: RefreshIndicator(
        onRefresh: () => _c.init(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _SectionTitle('에어컨'),
            _AirconCard(
              state: snap.aircon,
              onToggle: _c.toggleAc,
              onTempSlider: _c.setTargetTemperature,
              onSetMode: _c.setAcMode,
              onSetFanSpeed: _c.setAcFanSpeed,
              onSetTimer: _c.setAcTimer,
              loading: loading,
            ),
            const SizedBox(height: 24),
            _SectionTitle('환기'),
            _AirpassCard(
              isOn: snap.hrv.isOn,
              onToggle: _c.toggleHrv,
              loading: loading,
            ),
            const SizedBox(height: 24),
            _SectionTitle('전동 블라인드'),
            _BlindsCard(
              status: snap.blinds,
              onOpen: () => _c.setBlinds(BlindsStatus.open),
              onStop: () => _c.setBlinds(BlindsStatus.stop),
              onClose: () => _c.setBlinds(BlindsStatus.close),
              loading: loading,
            ),
            const SizedBox(height: 24),
            _SectionTitle('조명'),
            _LightsColumn(
              rooms: const ['거실', '침실', '주방'],
              snapshot: snap,
              onToggle: _c.toggleLight,
              onBrightness: _c.setBrightness,
              loading: loading,
            ),
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

// ================================ [1] 에어컨 카드 (기존 유지) ================================
class _AirconCard extends StatelessWidget {
  final AirconState state;
  final VoidCallback onToggle;
  final void Function(double) onTempSlider;
  final void Function(AcMode) onSetMode;
  final void Function(AcFanSpeed) onSetFanSpeed;
  final void Function(int) onSetTimer;
  final bool loading;

  const _AirconCard({required this.state, required this.onToggle, required this.onTempSlider, required this.onSetMode, required this.onSetFanSpeed, required this.onSetTimer, required this.loading});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn;
    final bgColor = on ? const Color(0xFFEBF7F8) : Colors.white;

    return Container(
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(on ? state.mode.label : '꺼짐', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: on ? Colors.black87 : Colors.grey)),
                  if (!on) ...[const SizedBox(height: 4), Text("실내 ${state.currentTemperature}°C", style: const TextStyle(fontSize: 13, color: Colors.grey))]
                ]),
                _PowerButton(on: on, onPressed: loading ? null : onToggle),
              ],
            ),
          ),
          if (on) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(children: [
                Text("희망 온도", style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text("${state.temperature}°C", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300, color: Colors.black87, letterSpacing: -1.5)),
                const SizedBox(height: 10),
                SliderTheme(
                  data: SliderThemeData(trackHeight: 6, activeTrackColor: const Color(0xFF4A6AFF), inactiveTrackColor: const Color(0xFFD1D9FF), thumbColor: const Color(0xFF4A6AFF), overlayColor: const Color(0xFF4A6AFF).withOpacity(0.1), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)),
                  child: Slider(value: state.temperature.toDouble(), min: 18, max: 30, divisions: 12, onChanged: loading ? null : onTempSlider),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: _ControlBox(title: "운전 모드", icon: _getModeIcon(state.mode), value: state.mode.label, color: const Color(0xFFE3F2FD), onTap: () => _showModePicker(context))),
                const SizedBox(width: 12),
                Expanded(child: _ControlBox(title: "바람 세기", icon: Icons.wind_power, value: _fanSpeedToString(state.fanSpeed), color: const Color(0xFFE0F2F1), onTap: () => _showFanSpeedPicker(context))),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.bedtime_outlined, color: Colors.orangeAccent),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("취침 예약", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  if (state.timerHours > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)), child: Text("${state.timerHours}시간 후 꺼짐", style: const TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _SleepTimerBtn(label: "해제", selected: state.timerHours == 0, onTap: () => onSetTimer(0)),
                  _SleepTimerBtn(label: "1시간", selected: state.timerHours == 1, onTap: () => onSetTimer(1)),
                  _SleepTimerBtn(label: "2시간", selected: state.timerHours == 2, onTap: () => onSetTimer(2)),
                  _SleepTimerBtn(label: "4시간", selected: state.timerHours == 4, onTap: () => onSetTimer(4)),
                ])
              ]),
            ),
            const SizedBox(height: 10),
          ] else ...[
            const SizedBox(height: 30),
            Center(child: Image.asset('assets/images/ac_off.png', height: 100, errorBuilder: (c, e, s) => const Icon(Icons.ac_unit, size: 80, color: Colors.black12))),
            const SizedBox(height: 40),
          ]
        ],
      ),
    );
  }

  IconData _getModeIcon(AcMode m) {
    switch (m) { case AcMode.cool: return Icons.ac_unit; case AcMode.heat: return Icons.wb_sunny; case AcMode.dry: return Icons.water_drop; case AcMode.fan: return Icons.air; case AcMode.auto: return Icons.hdr_auto; }
  }
  String _fanSpeedToString(AcFanSpeed s) {
    switch (s) { case AcFanSpeed.auto: return '자동'; case AcFanSpeed.low: return '약풍'; case AcFanSpeed.medium: return '중풍'; case AcFanSpeed.high: return '강풍'; }
  }
  void _showModePicker(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (_) => Container(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("운전 모드 선택", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 20), Wrap(spacing: 12, runSpacing: 12, children: AcMode.values.map((m) => _OptionChip(label: m.label, selected: state.mode == m, onSelected: () { onSetMode(m); Navigator.pop(context); })).toList())])));
  }
  void _showFanSpeedPicker(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (_) => Container(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("바람 세기 선택", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 20), Wrap(spacing: 12, runSpacing: 12, children: AcFanSpeed.values.map((s) => _OptionChip(label: _fanSpeedToString(s), selected: state.fanSpeed == s, onSelected: () { onSetFanSpeed(s); Navigator.pop(context); })).toList())])));
  }
}

// ================================ [2] 환기 카드 (리뉴얼) ================================
class _AirpassCard extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggle;
  final bool loading;
  const _AirpassCard({required this.isOn, required this.onToggle, required this.loading});

  @override
  Widget build(BuildContext context) {
    // 켜지면 민트색(Teal) 계열 배경
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
              child: const Text(
                "신선한 공기 순환 중 🍃",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.teal),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

// ================================ [3] 블라인드 카드 (리뉴얼) ================================
class _BlindsCard extends StatelessWidget {
  final BlindsStatus status;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback onClose;
  final bool loading;
  const _BlindsCard({required this.status, required this.onOpen, required this.onStop, required this.onClose, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.curtains_rounded, color: Colors.orangeAccent, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('전동 블라인드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 2),
                  Text('현재 상태: ${status.label}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _BlindCtrlBtn(icon: Icons.keyboard_arrow_up_rounded, label: "열기", isActive: status == BlindsStatus.open, onTap: loading ? null : onOpen)),
              const SizedBox(width: 12),
              Expanded(child: _BlindCtrlBtn(icon: Icons.stop_rounded, label: "정지", isActive: status == BlindsStatus.stop, onTap: loading ? null : onStop)),
              const SizedBox(width: 12),
              Expanded(child: _BlindCtrlBtn(icon: Icons.keyboard_arrow_down_rounded, label: "닫기", isActive: status == BlindsStatus.close, onTap: loading ? null : onClose)),
            ],
          )
        ],
      ),
    );
  }
}

class _BlindCtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  const _BlindCtrlBtn({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.orangeAccent : Colors.grey[400];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? Colors.orange[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? Colors.orangeAccent.withOpacity(0.5) : Colors.transparent),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isActive ? Colors.orange[800] : Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// ================================ [4] 조명 카드 (리뉴얼) ================================
class _LightsColumn extends StatelessWidget {
  final List<String> rooms;
  final IotSnapshot snapshot;
  final void Function(String) onToggle;
  final void Function(String, BrightnessLevel) onBrightness;
  final bool loading;
  const _LightsColumn({required this.rooms, required this.snapshot, required this.onToggle, required this.onBrightness, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final room in rooms) ...[
          _LightCard(
            room: room,
            state: snapshot.lights[room] ?? const LightRoomState(isOn: false, brightness: BrightnessLevel.normal),
            onToggle: () => onToggle(room),
            onBrightness: (b) => onBrightness(room, b),
            loading: loading,
          ),
          const SizedBox(height: 12),
        ]
      ],
    );
  }
}

class _LightCard extends StatelessWidget {
  final String room;
  final LightRoomState state;
  final VoidCallback onToggle;
  final void Function(BrightnessLevel) onBrightness;
  final bool loading;
  const _LightCard({required this.room, required this.state, required this.onToggle, required this.onBrightness, required this.loading});

  @override
  Widget build(BuildContext context) {
    final on = state.isOn;
    final bgColor = on ? const Color(0xFFFFF3E0) : Colors.white; // Soft Orange when ON

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: bgColor,
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
                  Icon(on ? Icons.lightbulb : Icons.lightbulb_outline, color: on ? Colors.orange : Colors.grey, size: 28),
                  const SizedBox(width: 12),
                  Text(room, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
              _PowerButton(on: on, onPressed: loading ? null : onToggle),
            ],
          ),
          if (on) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _OptionChip(label: "어둡게", selected: state.brightness == BrightnessLevel.dim, onSelected: () => onBrightness(BrightnessLevel.dim)),
                _OptionChip(label: "보통", selected: state.brightness == BrightnessLevel.normal, onSelected: () => onBrightness(BrightnessLevel.normal)),
                _OptionChip(label: "밝게", selected: state.brightness == BrightnessLevel.bright, onSelected: () => onBrightness(BrightnessLevel.bright)),
              ],
            )
          ]
        ],
      ),
    );
  }
}

// ---------------------- 공통 위젯들 ----------------------

class _PowerButton extends StatelessWidget {
  final bool on;
  final VoidCallback? onPressed;
  const _PowerButton({required this.on, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]),
      child: IconButton(
        icon: const Icon(Icons.power_settings_new),
        iconSize: 28,
        color: on ? Colors.blue : Colors.grey,
        onPressed: onPressed,
      ),
    );
  }
}

class _ControlBox extends StatelessWidget {
  final String title;
  final IconData icon;
  final String value;
  final Color color;
  final VoidCallback onTap;
  const _ControlBox({required this.title, required this.icon, required this.value, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: Colors.grey[700], size: 24), Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[300])]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])), const SizedBox(height: 2), Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87))])
        ]),
      ),
    );
  }
}

class _SleepTimerBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
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
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  const _OptionChip({required this.label, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: Colors.black87,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: selected ? Colors.transparent : Colors.grey.shade300)),
    );
  }
}