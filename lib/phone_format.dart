import 'package:flutter/services.dart';

/// 저장용: 하이픈/공백 제거해 숫자만 남김
String normalizePhoneDigits(String input) =>
    input.replaceAll(RegExp(r'[^0-9]'), '');

/// 보기용: 한국 번호 간단 하이픈 포맷
String formatKoreanPhone(String input) {
  final digits = normalizePhoneDigits(input);
  if (digits.isEmpty) return '';

  // 서울(02) 처리
  if (digits.startsWith('02')) {
    if (digits.length >= 10) {
      // 02-1234-5678 (2-4-4)
      final a = digits.substring(0, 2);
      final b = digits.substring(2, 6);
      final c = digits.substring(6, digits.length.clamp(6, 10));
      return [a, b, c].where((s) => s.isNotEmpty).join('-');
    } else if (digits.length >= 9) {
      // 02-123-4567 (2-3-4)
      final a = digits.substring(0, 2);
      final b = digits.substring(2, 5);
      final c = digits.substring(5, digits.length.clamp(5, 9));
      return [a, b, c].where((s) => s.isNotEmpty).join('-');
    }
  }

  // 11자리: 3-4-4 (모바일 010 등)
  if (digits.length >= 11) {
    final a = digits.substring(0, 3);
    final b = digits.substring(3, 7);
    final c = digits.substring(7, digits.length.clamp(7, 11));
    return [a, b, c].where((s) => s.isNotEmpty).join('-');
  }

  // 10자리: 3-3-4 (지역번호 3자리)
  if (digits.length == 10) {
    final a = digits.substring(0, 3);
    final b = digits.substring(3, 6);
    final c = digits.substring(6);
    return '$a-$b-$c';
  }

  // 8자리: 4-4
  if (digits.length == 8) {
    return '${digits.substring(0, 4)}-${digits.substring(4)}';
  }

  // 나머지: 앞에서부터 3-4-나머지 형태로 최대한 보기 좋게
  if (digits.length > 7) {
    final a = digits.substring(0, 3);
    final b = digits.substring(3, 7);
    final c = digits.substring(7);
    return c.isEmpty ? '$a-$b' : '$a-$b-$c';
  }

  // 짧은 길이는 하이픈 없이 그대로
  return digits;
}

/// 입력 중 실시간 하이픈 적용 포매터
class KoreanPhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = formatKoreanPhone(newValue.text);
    // 커서 위치를 끝으로 보정 (간단/안전)
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }
}
