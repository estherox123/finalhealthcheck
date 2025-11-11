// lib/pages/device_control_page.dart
/// 기기 제어 페이지. IoT 연동 필요.

import 'package:flutter/material.dart';

import '../data/iot/device_control_controller.dart';
import '../data/iot/iot_repository.dart';
import '../data/iot/mock_iot_api.dart';
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
    _c = DeviceControlController(IotRepository(MockIotApi()));
    _c.addListener(_onChange);
    _c.init();
  }

  void _onChange() => setState(() {});
  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _c.snapshot;
    final loading = _c.status != IotStatus.ready;

    return Scaffold(
      appBar: AppBar(title: const Text('기기 제어')),
      body: RefreshIndicator(
        onRefresh: () => _c.init(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // ================= 에어컨 =================
            _SectionTitle('에어컨'),
            _AirconCard(
              state: snap.aircon,
              onToggle: _c.toggleAc,
              onTempDelta: _c.acTempDelta,
              onSetMode: _c.setAcMode,
              onSetTimer: _c.setAcTimer,
              loading: loading,
            ),
            const SizedBox(height: 16),

            // ========== 환기(무덕트, 에어패스) ==========
            // ※ 백엔드 변경 없이 기존 HRV on/off 상태 재사용
            _SectionTitle('환기'),
            _AirpassCard(
              isOn: snap.hrv.isOn,
              onToggle: _c.toggleHrv,
              loading: loading,
            ),
            const SizedBox(height: 16),

            // ================= 블라인드 =================
            _SectionTitle('전동 블라인드'),
            _BlindsCard(
              status: snap.blinds,
              onOpen: () => _c.setBlinds(BlindsStatus.open),
              onStop: () => _c.setBlinds(BlindsStatus.stop),
              onClose: () => _c.setBlinds(BlindsStatus.close),
              loading: loading,
            ),
            const SizedBox(height: 16),

            // ================== 조명 ===================
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

/* --------------------------- 공통 타이틀 --------------------------- */
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

/* ================================ 에어컨 ================================ */

class _AirconCard extends StatelessWidget {
  final AirconState state;
  final VoidCallback onToggle;
  final void Function(int delta) onTempDelta;
  final void Function(AcMode mode) onSetMode;
  final void Function(int hours) onSetTimer;
  final bool loading;

  const _AirconCard({
    required this.state,
    required this.onToggle,
    required this.onTempDelta,
    required this.onSetMode,
    required this.onSetTimer,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn;
    final int temp = state.temperature;
    final AcMode mode = state.mode;
    final int timer = state.timerHours;

    return _Card(
      color: Colors.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(
            icon: Icons.ac_unit,
            color: Colors.blue,
            title: '에어컨',
            trailing: _PrimaryButton(
              label: on ? '켜짐' : '꺼짐',
              onPressed: loading ? null : onToggle,
              active: on,
              color: Colors.blue,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: on
                ? Column(
              key: const ValueKey('ac-on'),
              children: [
                const SizedBox(height: 8),
                _TempControlRow(
                  temp: temp,
                  onMinus: loading ? null : () => onTempDelta(-1),
                  onPlus: loading ? null : () => onTempDelta(1),
                  color: Colors.blue,
                ),
                const SizedBox(height: 12),
                _ModeChips<AcMode>(
                  label: '모드',
                  value: mode,
                  items: const {
                    AcMode.cool: '냉방',
                    AcMode.heat: '난방',
                    AcMode.fan: '송풍',
                  },
                  onSelected: loading ? null : onSetMode,
                ),
                const SizedBox(height: 12),
                _TimerGrid2x2(
                  value: timer, // 0/1/2/4
                  onSelected: loading ? null : onSetTimer,
                  color: Colors.blue,
                ),
              ],
            )
                : const SizedBox(height: 4, key: ValueKey('ac-off')),
          ),
        ],
      ),
    );
  }
}

/* ===== 타이머 2x2 그리드 (해제 / 1시간 / 2시간 / 4시간) ===== */

class _TimerGrid2x2 extends StatelessWidget {
  final int value; // 0/1/2/4
  final void Function(int v)? onSelected;
  final Color color;
  const _TimerGrid2x2({
    required this.value,
    required this.onSelected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const items = [0, 1, 2, 4];
    return LayoutBuilder(builder: (context, c) {
      final double w = c.maxWidth;
      final double h = w < 300 ? 44 : 50;
      final padV = w < 300 ? 10.0 : 12.0;

      return SizedBox(
        height: h * 2 + 8,
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: (w / 2 - 8) / h,
          children: items.map((hVal) {
            final sel = hVal == value;
            return ElevatedButton(
              onPressed: onSelected == null ? null : () => onSelected!(hVal),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: padV),
                backgroundColor: sel ? color : Colors.grey.shade200,
                foregroundColor: sel ? Colors.white : Colors.grey.shade800,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(hVal == 0 ? '해제' : '${hVal}시간'),
              ),
            );
          }).toList(),
        ),
      );
    });
  }
}

/* ======================= 환기(무덕트: 에어패스) ======================= */

class _AirpassCard extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggle;
  final bool loading;

  const _AirpassCard({
    required this.isOn,
    required this.onToggle,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final color = Colors.teal;

    return _Card(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(
            icon: Icons.air_outlined,
            color: color,
            title: '환기(무덕트)',
            trailing: _PrimaryButton(
              label: isOn ? '켜짐' : '꺼짐',
              onPressed: loading ? null : onToggle,
              active: isOn,
              color: color,
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: isOn
                ? Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : onToggle,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    child: const Text('가동 중'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '신선한 공기 순환 중',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[700]),
                ),
              ],
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}


/* ============================ 전동 블라인드 ============================ */

class _BlindsCard extends StatelessWidget {
  final BlindsStatus status;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback onClose;
  final bool loading;

  const _BlindsCard({
    required this.status,
    required this.onOpen,
    required this.onStop,
    required this.onClose,
    required this.loading,
  });

  String _label(BlindsStatus s) {
    switch (s) {
      case BlindsStatus.open:
        return '열림';
      case BlindsStatus.close:
        return '닫힘';
      case BlindsStatus.stop:
      default:
        return '정지';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber;

    return _Card(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(
            icon: Icons.wb_sunny_outlined,
            color: color,
            title: '전동 블라인드',
          ),
          const SizedBox(height: 6),
          Text(
            '현재 상태: ${_label(status)}',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[700], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _BigAction(
                  icon: Icons.keyboard_arrow_up_rounded,
                  label: '열기',
                  color: Colors.green,
                  onPressed: loading ? null : onOpen,
                  selected: status == BlindsStatus.open,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigAction(
                  icon: Icons.stop_rounded,
                  label: '정지',
                  color: Colors.grey,
                  onPressed: loading ? null : onStop,
                  selected: status == BlindsStatus.stop,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigAction(
                  icon: Icons.keyboard_arrow_down_rounded,
                  label: '닫기',
                  color: Colors.red,
                  onPressed: loading ? null : onClose,
                  selected: status == BlindsStatus.close,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

/* ================================ 조명 ================================ */

class _LightsColumn extends StatelessWidget {
  final List<String> rooms;
  final IotSnapshot snapshot;
  final void Function(String room) onToggle;
  final void Function(String room, BrightnessLevel b) onBrightness;
  final bool loading;

  const _LightsColumn({
    required this.rooms,
    required this.snapshot,
    required this.onToggle,
    required this.onBrightness,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final room in rooms) ...[
          _LightCard(
            room: room,
            state: snapshot.lights[room] ??
                const LightRoomState(
                    isOn: false, brightness: BrightnessLevel.normal),
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
  final void Function(BrightnessLevel b) onBrightness;
  final bool loading;

  const _LightCard({
    required this.room,
    required this.state,
    required this.onToggle,
    required this.onBrightness,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final on = state.isOn;
    final b = state.brightness;

    return _Card(
      color: Colors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(
            icon: Icons.lightbulb_outline,
            color: Colors.orange,
            title: room,
            trailing: _PrimaryButton(
              label: on ? '켜짐' : '꺼짐',
              onPressed: loading ? null : onToggle,
              active: on,
              color: Colors.orange,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: on
                ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ModeChips<BrightnessLevel>(
                label: '밝기',
                value: b,
                items: const {
                  BrightnessLevel.dim: '어둡게',
                  BrightnessLevel.normal: '보통',
                  BrightnessLevel.bright: '밝게',
                },
                onSelected: loading ? null : onBrightness,
                center: true,
              ),
            )
                : const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }
}

/* ============================== 공용 위젯 ============================== */

class _Card extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Card({required this.color, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(.30)),
    ),
    child: child,
  );
}

class _HeaderRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget? trailing;
  const _HeaderRow(
      {required this.icon, required this.color, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: color.withOpacity(.18),
        child: Icon(icon, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color color;
  const _PrimaryButton(
      {required this.label,
        required this.onPressed,
        required this.active,
        required this.color});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: active ? color : Colors.grey.shade200,
      foregroundColor: active ? Colors.white : Colors.grey.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}

class _TempControlRow extends StatelessWidget {
  final int temp;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final Color color;
  const _TempControlRow(
      {required this.temp, required this.onMinus, required this.onPlus, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _RoundIconBtn(icon: Icons.remove, onTap: onMinus, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$temp°C',
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ),
      const SizedBox(width: 10),
      _RoundIconBtn(icon: Icons.add, onTap: onPlus, color: color),
    ],
  );
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  const _RoundIconBtn({required this.icon, required this.onTap, required this.color});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: Ink(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color),
    ),
  );
}

class _ModeChips<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final void Function(T v)? onSelected;
  final bool center;

  const _ModeChips({
    required this.label,
    required this.value,
    required this.items,
    required this.onSelected,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    final wrapAlign = center ? WrapAlignment.center : WrapAlignment.start;

    final column = Column(
      crossAxisAlignment:
      center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: wrapAlign,
          runAlignment: wrapAlign,
          spacing: 8,
          runSpacing: 8,
          children: items.keys.map((k) {
            final sel = k == value;
            return ChoiceChip(
              label: Text(items[k]!),
              selected: sel,
              onSelected: onSelected == null ? null : (_) => onSelected!(k),
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: sel ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
              side: const BorderSide(color: Colors.black12),
            );
          }).toList(),
        ),
      ],
    );

    return center ? SizedBox(width: double.infinity, child: column) : column;
  }
}

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool selected;

  const _BigAction(
      {required this.icon,
        required this.label,
        required this.color,
        required this.onPressed,
        this.selected = false});

  @override
  Widget build(BuildContext context) {
    final Color bgBase = selected ? color : color.withOpacity(.12);
    final Color fgBase = selected ? Colors.white : color;

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: bgBase,
        foregroundColor: fgBase,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ).merge(
        ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return selected ? color.withOpacity(.90) : color.withOpacity(.20);
            }
            return bgBase;
          }),
          foregroundColor: MaterialStatePropertyAll(fgBase),
        ),
      ),
    );
  }
}
