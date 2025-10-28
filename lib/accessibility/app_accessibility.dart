import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextPreset { normal, large, xlarge }

@immutable
class SeniorTheme extends ThemeExtension<SeniorTheme> {
  final double textScale;      // 1.0, 1.15, 1.3
  final bool highContrast;     // 대비 강화
  final double minButtonHeight; // 버튼 최소 높이

  const SeniorTheme({
    required this.textScale,
    required this.highContrast,
    required this.minButtonHeight,
  });

  @override
  SeniorTheme copyWith({
    double? textScale,
    bool? highContrast,
    double? minButtonHeight,
  }) => SeniorTheme(
    textScale: textScale ?? this.textScale,
    highContrast: highContrast ?? this.highContrast,
    minButtonHeight: minButtonHeight ?? this.minButtonHeight,
  );

  @override
  SeniorTheme lerp(ThemeExtension<SeniorTheme>? other, double t) {
    if (other is! SeniorTheme) return this;
    return SeniorTheme(
      textScale: lerpDouble(textScale, other.textScale, t) ?? textScale,
      highContrast: t < .5 ? highContrast : other.highContrast,
      minButtonHeight: lerpDouble(minButtonHeight, other.minButtonHeight, t) ?? minButtonHeight,
    );
  }
}

/// 전역 컨트롤러: 앱 시작 시 로드 → MaterialApp의 theme에 반영
class AccessibilityController extends ChangeNotifier {
  AccessibilityController._();
  static final AccessibilityController instance = AccessibilityController._();

  TextPreset preset = TextPreset.normal;
  bool highContrast = false;
  double minButtonHeight = 44;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    preset = TextPreset.values[p.getInt('acc_preset') ?? 0];
    highContrast = p.getBool('acc_contrast') ?? false;
    minButtonHeight = p.getDouble('acc_btn_h') ?? 44;
    notifyListeners();
  }

  Future<void> update({
    TextPreset? preset,
    bool? highContrast,
    double? minButtonHeight,
  }) async {
    if (preset != null) this.preset = preset;
    if (highContrast != null) this.highContrast = highContrast;
    if (minButtonHeight != null) this.minButtonHeight = minButtonHeight!;
    final p = await SharedPreferences.getInstance();
    await p.setInt('acc_preset', this.preset.index);
    await p.setBool('acc_contrast', this.highContrast);
    await p.setDouble('acc_btn_h', this.minButtonHeight);
    notifyListeners();
  }

  SeniorTheme currentExtension() {
    final scale = switch (preset) {
      TextPreset.normal => 1.0,
      TextPreset.large => 1.15,
      TextPreset.xlarge => 1.30,
    };
    return SeniorTheme(
      textScale: scale,
      highContrast: highContrast,
      minButtonHeight: minButtonHeight,
    );
  }
}

double? lerpDouble(double a, double b, double t) => a + (b - a) * t;
