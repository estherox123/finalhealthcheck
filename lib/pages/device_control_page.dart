// lib/pages/device_control_page.dart
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
    final snap = _c.snapshot; // IotSnapshot?
    final loading = snap == null;

    return Scaffold(
      appBar: AppBar(title: const Text('기기 제어')),
      body: RefreshIndicator(
        // 컨트롤러에 refresh가 없다 했으니 init()을 재호출해 재로딩
        onRefresh: () => _c.init(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // ============ 에어컨 (AcMode/컨트롤러 시그니처에 맞춤) ============
            _SectionTitle('에어컨'),
            _AirconCard(
              state: snap?.aircon,                   // AcState?
              onToggle: () => _c.toggleAc(),
              onTempDelta: (d) => _c.acTempDelta(d), // int delta
              onSetMode: (m) => _c.setAcMode(m),     // AcMode
              onSetTimer: (h) => _c.setAcTimer(h),   // int hours(0,1,2,4)
              loading: loading,
            ),
            const SizedBox(height: 16),

            // ============ 전동 블라인드 (setBlinds + 단순 상태) ============
            _SectionTitle('전동 블라인드'),
            _BlindsCard(
              status: snap?.blinds, // BlindsStatus? (open/close/stop 중 하나)
              onOpen: () => _c.setBlinds(BlindsStatus.open),
              onStop: () => _c.setBlinds(BlindsStatus.stop),
              onClose: () => _c.setBlinds(BlindsStatus.close),
              loading: loading,
            ),
            const SizedBox(height: 16),

            // ============ 조명(방별 큰 카드: 거실/침실/주방) ===============
            _SectionTitle('조명'),
            _LightsRow(
              rooms: const ['거실', '침실', '주방'],
              snapshot: snap,
              onToggle: (room) => _c.toggleLight(room),
              onBrightness: (room, b) => _c.setBrightness(room, b),
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
    child: Text(text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800)),
  );
}

/* ================================ 에어컨 ================================ */

class _AirconCard extends StatelessWidget {
  final dynamic state;
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
    final bool on   = (state?.isOn as bool?) ?? false;
    final int  temp = (state?.temperature as int?) ?? 24;
    final AcMode mode = (state?.mode as AcMode?) ?? AcMode.cool;
    final int  timer  = (state?.timerHours as int?) ?? 0;

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
            duration: const Duration(milliseconds: 200),
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
                  // const로 박으면 “맵 키는 상수여야” 오류가 날 수 있어요 → 일반 Map 사용
                  items: {
                    AcMode.cool: '냉방',
                    AcMode.heat: '난방',
                    AcMode.fan: '송풍',
                  },
                  onSelected: loading ? null : onSetMode,
                ),
                const SizedBox(height: 12),
                _TimerChips(
                  value: timer,                  // 0/1/2/4
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

/* ============================ 전동 블라인드 ============================ */

class _BlindsCard extends StatelessWidget {
  final BlindsStatus? status; // open/close/stop 중 하나
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
    final s = status ?? BlindsStatus.stop;
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
            '현재 상태: ${_label(s)}',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[700], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          // 큰 3버튼(열기/정지/닫기) – 직관 위주
          Row(
            children: [
              Expanded(
                child: _BigAction(
                  icon: Icons.keyboard_arrow_up_rounded,
                  label: '열기',
                  color: Colors.green,
                  onPressed: loading ? null : onOpen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigAction(
                  icon: Icons.stop_rounded,
                  label: '정지',
                  color: Colors.grey,
                  onPressed: loading ? null : onStop,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigAction(
                  icon: Icons.keyboard_arrow_down_rounded,
                  label: '닫기',
                  color: Colors.red,
                  onPressed: loading ? null : onClose,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ================================ 조명 ================================ */

class _LightsRow extends StatelessWidget {
  final List<String> rooms;
  final IotSnapshot? snapshot;
  final void Function(String room) onToggle;
  final void Function(String room, BrightnessLevel b) onBrightness;
  final bool loading;

  const _LightsRow({
    required this.rooms,
    required this.snapshot,
    required this.onToggle,
    required this.onBrightness,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cross = w < 420 ? 1 : (w < 680 ? 2 : 3);

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rooms.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        itemBuilder: (_, i) {
          final room = rooms[i];
          final LightRoomState? s = snapshot?.lights[room];
          final on = s?.isOn ?? false;
          final b = s?.brightness ?? BrightnessLevel.normal;

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
                    onPressed: loading ? null : () => onToggle(room),
                    active: on,
                    color: Colors.orange,
                  ),
                ),
                AnimatedCrossFade(
                  crossFadeState:
                  on ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                  firstChild: const SizedBox(height: 4),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ModeChips<BrightnessLevel>(
                      label: '밝기',
                      value: b,
                      items: {
                        BrightnessLevel.dim: '어둡게',
                        BrightnessLevel.normal: '보통',
                        BrightnessLevel.bright: '밝게',
                      },
                      onSelected:
                      loading ? null : (v) => onBrightness(room, v),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
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
              ?.copyWith(fontWeight: FontWeight.w800),
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
      {required this.label, required this.onPressed, required this.active, required this.color});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: active ? color : Colors.grey.shade200,
      foregroundColor: active ? Colors.white : Colors.grey.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          child: Text('$temp°C',
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
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
  final Map<T, String> items;           // const 강제 X (상수 오류 방지)
  final void Function(T v)? onSelected;
  const _ModeChips({
    required this.label,
    required this.value,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[700])),
      const SizedBox(height: 6),
      Wrap(
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
}

class _TimerChips extends StatelessWidget {
  final int value; // 0/1/2/4
  final void Function(int v)? onSelected;
  final Color color;
  const _TimerChips({required this.value, required this.onSelected, required this.color});

  @override
  Widget build(BuildContext context) {
    final items = [0, 1, 2, 4];
    return LayoutBuilder(builder: (context, c) {
      // 버튼이 세로로 꺾이지 않게 폭/패딩 자동조정
      final isTight = c.maxWidth < 320;
      final btnPad = EdgeInsets.symmetric(
        horizontal: isTight ? 10 : 14,
        vertical: isTight ? 10 : 12,
      );

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((h) {
          final sel = h == value;
          return ElevatedButton(
            onPressed: onSelected == null ? null : () => onSelected!(h),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: btnPad,
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: sel ? color : Colors.grey.shade200,
              foregroundColor: sel ? Colors.white : Colors.grey.shade800,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: Text(h == 0 ? '해제' : '${h}시간'),
          );
        }).toList(),
      );
    });
  }
}

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  const _BigAction(
      {required this.icon, required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 14),
      backgroundColor: color.withOpacity(.12),
      foregroundColor: color,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    ),
  );
}
