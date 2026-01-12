import 'package:flutter/material.dart';
import '../data/iot/device_control_controller.dart';
import '../data/iot/home_assistant_api.dart';
import '../data/iot/home_assistant_options.dart';
import '../data/iot/iot_repository.dart';
import '../data/iot/models.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  late final DeviceControlController _c;

  @override
  void initState() {
    super.initState();
    // 기존 컨트롤러 로직 재사용 (싱글톤으로 관리하면 더 좋지만, 일단 개별 생성)
    final api = HomeAssistantApi(options: HomeAssistantOptions.fromEnv());
    final repo = IotRepository(api);
    _c = DeviceControlController(repo);
    _c.addListener(_update);
    _c.init();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_update);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _c.snapshot.adminSettings;
    final loading = _c.status == IotStatus.loading;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('자동화 규칙 설정', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (loading)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(title: "계절 모드", icon: Icons.calendar_month),
          _SeasonSelector(
            currentMode: settings.seasonMode,
            onChanged: (val) => _c.repo.setSeasonMode(val),
          ),
          const SizedBox(height: 30),

          _SectionHeader(title: "여름철 (냉방) 규칙", icon: Icons.wb_sunny, color: Colors.orange),
          _SliderCard(
            title: "냉방 시작 온도",
            desc: "실내 온도가 이보다 높으면 냉방 가동",
            value: settings.summerTriggerTemp,
            min: 24, max: 32,
            onChangedEnd: (v) => _c.repo.setAdminNumber('admin_summer_trigger_temp', v),
          ),
          _SliderCard(
            title: "냉방 목표 온도",
            desc: "냉방 시 맞출 희망 온도",
            value: settings.summerTargetTemp,
            min: 18, max: 28,
            onChangedEnd: (v) => _c.repo.setAdminNumber('admin_summer_target_temp', v),
          ),
          const SizedBox(height: 30),

          _SectionHeader(title: "겨울철 (난방) 규칙", icon: Icons.ac_unit, color: Colors.blue),
          _SliderCard(
            title: "난방 시작 온도",
            desc: "실내 온도가 이보다 낮으면 난방 가동",
            value: settings.winterTriggerTemp,
            min: 15, max: 25,
            onChangedEnd: (v) => _c.repo.setAdminNumber('admin_winter_trigger_temp', v),
          ),
          _SliderCard(
            title: "난방 목표 온도",
            desc: "난방 시 맞출 희망 온도",
            value: settings.winterTargetTemp,
            min: 20, max: 30,
            onChangedEnd: (v) => _c.repo.setAdminNumber('admin_winter_target_temp', v),
          ),
          const SizedBox(height: 30),

          _SectionHeader(title: "습도 관리", icon: Icons.water_drop, color: Colors.blueAccent),
          _SliderCard(
            title: "제습 시작 습도",
            desc: "습도가 이보다 높으면 제습/냉방 가동",
            value: settings.humidityTrigger,
            min: 50, max: 90,
            unit: "%",
            onChangedEnd: (v) => _c.repo.setAdminNumber('admin_humidity_trigger', v),
          ),
          _SliderCard(
            title: "목표 습도",
            desc: "제습 시 도달하려는 습도",
            value: settings.humidityTarget,
            min: 40, max: 70,
            unit: "%",
            onChangedEnd: (v) => _c.repo.setAdminNumber('admin_humidity_target', v),
          ),
        ],
      ),
    );
  }
}

// ---- 위젯들 ----

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({required this.title, required this.icon, this.color = Colors.black87});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  final String currentMode;
  final Function(String) onChanged;

  const _SeasonSelector({required this.currentMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const modes = ['Auto (사계절 감지)', 'Summer (여름 고정)', 'Winter (겨울 고정)', 'Off (자동화 끄기)'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: modes.contains(currentMode) ? currentMode : modes.first,
          isExpanded: true,
          items: modes.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

class _SliderCard extends StatefulWidget {
  final String title;
  final String desc;
  final double value;
  final double min;
  final double max;
  final String unit;
  final Function(double) onChangedEnd;

  const _SliderCard({
    required this.title, required this.desc, required this.value,
    required this.min, required this.max, required this.onChangedEnd,
    this.unit = "°C"
  });

  @override
  State<_SliderCard> createState() => _SliderCardState();
}

class _SliderCardState extends State<_SliderCard> {
  double _localValue = 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant _SliderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) _localValue = widget.value;
  }

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text("${_localValue.toStringAsFixed(1)}${widget.unit}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.indigo)),
            ],
          ),
          const SizedBox(height: 4),
          Text(widget.desc, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(trackHeight: 4, activeTrackColor: Colors.indigo, thumbColor: Colors.indigo, overlayColor: Colors.indigo.withOpacity(0.1)),
            child: Slider(
              value: _localValue.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: ((widget.max - widget.min) * 2).toInt(), // 0.5 단위
              label: _localValue.toStringAsFixed(1),
              onChanged: (v) => setState(() { _dragging = true; _localValue = v; }),
              onChangeEnd: (v) {
                _dragging = false;
                widget.onChangedEnd(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}