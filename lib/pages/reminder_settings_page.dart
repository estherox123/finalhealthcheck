//reminder_settings_page.dart
/// 리마인더 설정 페이지 - 잠혈검사 (+a). 추가할 것 생각 필요.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/reminder_service.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});
  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  bool occultOn = false;
  TimeOfDay occultTime = const TimeOfDay(hour: 8, minute: 0);
  int occultWeekday = DateTime.saturday; // 1=월 … 7=일

  bool windOn = false;
  TimeOfDay windTime = const TimeOfDay(hour: 22, minute: 0);

  bool actOn = false;
  TimeOfDay actTime = const TimeOfDay(hour: 19, minute: 0);

  final wdMap = const {
    DateTime.monday: '월',
    DateTime.tuesday: '화',
    DateTime.wednesday: '수',
    DateTime.thursday: '목',
    DateTime.friday: '금',
    DateTime.saturday: '토',
    DateTime.sunday: '일',
  };

  @override
  void initState() {
    super.initState();
    _load();
    // 서비스 초기화 (await 불가한 위치라 fire-and-forget)
    ReminderService.instance.init();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      occultOn = p.getBool('occult_on') ?? false;
      occultWeekday = p.getInt('occult_weekday') ?? DateTime.saturday;
      occultTime = TimeOfDay(
        hour: p.getInt('occult_h') ?? 8,
        minute: p.getInt('occult_m') ?? 0,
      );

      windOn = p.getBool('winddown_on') ?? false;
      windTime = TimeOfDay(
        hour: p.getInt('winddown_h') ?? 22,
        minute: p.getInt('winddown_m') ?? 0,
      );

      actOn = p.getBool('activity_on') ?? false;
      actTime = TimeOfDay(
        hour: p.getInt('activity_h') ?? 19,
        minute: p.getInt('activity_m') ?? 0,
      );
    });
  }

  Future<void> _saveOccultPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('occult_on', occultOn);
    await p.setInt('occult_weekday', occultWeekday);
    await p.setInt('occult_h', occultTime.hour);
    await p.setInt('occult_m', occultTime.minute);
  }

  Future<void> _saveWindPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('winddown_on', windOn);
    await p.setInt('winddown_h', windTime.hour);
    await p.setInt('winddown_m', windTime.minute);
  }

  Future<void> _saveActPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('activity_on', actOn);
    await p.setInt('activity_h', actTime.hour);
    await p.setInt('activity_m', actTime.minute);
  }

  Future<void> _pickTime(TimeOfDay cur, ValueChanged<TimeOfDay> onPicked) async {
    final v = await showTimePicker(context: context, initialTime: cur);
    if (v != null) onPicked(v);
  }

  @override
  Widget build(BuildContext context) {
    final svc = ReminderService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('리마인더 설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section('잠혈 검사(주 1회)'),
          SwitchListTile(
            title: const Text('잠혈 검사 알림 켜기'),
            value: occultOn,
            subtitle: Text('매주 ${wdMap[occultWeekday]}요일 • ${occultTime.format(context)}'),
            onChanged: (v) async {
              setState(() => occultOn = v);
              await _saveOccultPrefs();
              if (v) {
                final success = await svc.enableOccultWeekly(
                  weekdays: [occultWeekday],
                  hour: occultTime.hour,
                  minute: occultTime.minute,
                );
                debugPrint('enableOccultWeekly -> $success / ${occultWeekday} ${occultTime.format(context)}');
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('알림 설정 실패. 알림 권한을 확인해주세요.')),
                  );
                }
              } else {
                await svc.disableOccultWeekly();
              }
            },
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: const Text('시간', style: TextStyle(fontSize: 12)),
                  onPressed: () => _pickTime(occultTime, (t) async {
                    setState(() => occultTime = t);
                    await _saveOccultPrefs();
                    if (occultOn) {
                      final success = await svc.enableOccultWeekly(
                        weekdays: [occultWeekday],
                        hour: t.hour,
                        minute: t.minute,
                      );
                      if (!success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('알림 설정 실패')),
                        );
                      }
                    }
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('${wdMap[occultWeekday]}', style: const TextStyle(fontSize: 12)),
                  onPressed: () async {
                    final wd = await showModalBottomSheet<int>(
                      context: context,
                      builder: (_) => _WeekdaySheet(
                        selected: occultWeekday,
                        wdMap: wdMap,
                      ),
                    );
                    if (wd != null) {
                      setState(() => occultWeekday = wd);
                      await _saveOccultPrefs();
                      if (occultOn) {
                        final success = await svc.enableOccultWeekly(
                          weekdays: [wd],
                          hour: occultTime.hour,
                          minute: occultTime.minute,
                        );
                        if (!success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('알림 설정 실패')),
                          );
                        }
                      }
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _Section('취침 전 안정화(매일)'),
          SwitchListTile(
            title: const Text('취침 전 안정화 알림'),
            value: windOn,
            subtitle: Text('매일 ${windTime.format(context)}'),
            onChanged: (v) async {
              setState(() => windOn = v);
              await _saveWindPrefs();
              if (v) {
                final success = await svc.enableWindDownDaily(
                  hour: windTime.hour,
                  minute: windTime.minute,
                );
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('알림 설정 실패. 알림 권한을 확인해주세요.')),
                  );
                }
              } else {
                await svc.disableWindDownDaily();
              }
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time),
            label: const Text('시간 설정'),
            onPressed: () => _pickTime(windTime, (t) async {
              setState(() => windTime = t);
              await _saveWindPrefs();
              if (windOn) {
                final success = await svc.enableWindDownDaily(
                  hour: t.hour,
                  minute: t.minute,
                );
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('알림 설정 실패')),
                  );
                }
              }
            }),
          ),

          const SizedBox(height: 20),
          _Section('활동 리마인더(매일)'),
          SwitchListTile(
            title: const Text('가벼운 활동 알림'),
            value: actOn,
            subtitle: Text('매일 ${actTime.format(context)}'),
            onChanged: (v) async {
              setState(() => actOn = v);
              await _saveActPrefs();
              if (v) {
                final success = await svc.enableActivityDaily(
                  hour: actTime.hour,
                  minute: actTime.minute,
                );
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('알림 설정 실패. 알림 권한을 확인해주세요.')),
                  );
                }
              } else {
                await svc.disableActivityDaily();
              }
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time),
            label: const Text('시간 설정'),
            onPressed: () => _pickTime(actTime, (t) async {
              setState(() => actTime = t);
              await _saveActPrefs();
              if (actOn) {
                final success = await svc.enableActivityDaily(
                  hour: t.hour,
                  minute: t.minute,
                );
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('알림 설정 실패')),
                  );
                }
              }
            }),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _WeekdaySheet extends StatelessWidget {
  final int selected;
  final Map<int, String> wdMap;
  const _WeekdaySheet({required this.selected, required this.wdMap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        const Text('요일 선택',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(),
        for (final wd in const [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
          DateTime.saturday,
          DateTime.sunday,
        ])
          RadioListTile<int>(
            title: Text(wdMap[wd]!),
            value: wd,
            groupValue: selected,
            onChanged: (v) => Navigator.pop(context, v),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
