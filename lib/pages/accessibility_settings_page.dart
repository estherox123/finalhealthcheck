//lib/pages/accessibility_settings_page.dart
///버튼 크기 슬라이더 / 글자 크기 프리셋
///현재 사용 안하는중

import 'package:flutter/material.dart';
import '../accessibility/app_accessibility.dart';

class AccessibilitySettingsPage extends StatefulWidget {
  const AccessibilitySettingsPage({super.key});
  @override
  State<AccessibilitySettingsPage> createState() => _AccessibilitySettingsPageState();
}

class _AccessibilitySettingsPageState extends State<AccessibilitySettingsPage> {
  final acc = AccessibilityController.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가독성/접근성 설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section('글자 크기 프리셋'),
          Column(
            children: [
              RadioListTile<TextPreset>(
                title: const Text('보통'),
                value: TextPreset.normal,
                groupValue: acc.preset,
                onChanged: (v) => setState(() => acc.update(preset: v)),
              ),
              RadioListTile<TextPreset>(
                title: const Text('라지 (약 15%)'),
                value: TextPreset.large,
                groupValue: acc.preset,
                onChanged: (v) => setState(() => acc.update(preset: v)),
              ),
              RadioListTile<TextPreset>(
                title: const Text('엑스트라 라지 (약 30%)'),
                value: TextPreset.xlarge,
                groupValue: acc.preset,
                onChanged: (v) => setState(() => acc.update(preset: v)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section('버튼 크기'),
          Slider(
            min: 40, max: 64, divisions: 6,
            value: acc.minButtonHeight,
            label: '${acc.minButtonHeight.toStringAsFixed(0)} px',
            onChanged: (v) => setState(() => acc.update(minButtonHeight: v)),
          ),
          const SizedBox(height: 12),
          _Section('고대비(텍스트/테두리 강조)'),
          SwitchListTile(
            title: const Text('고대비 모드'),
            value: acc.highContrast,
            onChanged: (v) => setState(() => acc.update(highContrast: v)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: const Text('완료'),
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
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
  );
}
