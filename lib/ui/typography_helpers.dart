import 'package:flutter/material.dart';

/// 한글 텍스트만 살짝 키우는 헬퍼
TextStyle? krStyle(TextStyle? base, {
  double scale = 1.16,
  FontWeight? fontWeight,
  Color? color,
}) {
  if (base == null) return null;
  return base.copyWith(
    fontSize: (base.fontSize ?? 14) * scale,
    fontWeight: fontWeight ?? base.fontWeight,
    color: color ?? base.color,
  );
}

/// 숫자(크게) + 단위(작게) 조합 위젯
class NumUnitText extends StatelessWidget {
  final String number;
  final String unit;
  final Color? color;
  final double numberScale;
  final double unitScale;
  final FontWeight numberWeight;

  const NumUnitText(
      this.number,
      this.unit, {
        super.key,
        this.color,
        this.numberScale = 1.30,
        this.unitScale = 0.92,
        this.numberWeight = FontWeight.w800,
      });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.titleLarge ?? const TextStyle(fontSize: 20);
    final numStyle = base.copyWith(
      fontSize: (base.fontSize ?? 20) * numberScale,
      fontWeight: numberWeight,
      color: color ?? base.color,
      height: 1.0,
    );
    final unitStyle = base.copyWith(
      fontSize: (base.fontSize ?? 20) * unitScale,
      fontWeight: FontWeight.w600,
      color: color ?? base.color,
      height: 1.1,
    );
    return RichText(text: TextSpan(children: [
      TextSpan(text: number, style: numStyle),
      TextSpan(text: unit, style: unitStyle),
    ]));
  }
}
