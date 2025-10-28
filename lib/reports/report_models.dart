import 'package:flutter/material.dart';

enum ReportGrade { good, warn, bad, unknown }

class HealthReportData {
  // 메타
  final DateTime generatedAt;
  final String subjectName; // 사용자 이름 혹은 익명 식별자
  final String rangeLabel;  // 예: '오늘', '최근 7일', '최근 30일'

  // 활동
  final int? steps;            // 오늘 걸음 / 평균 걸음 (선택)
  final ReportGrade stepsGrade; // good/warn/bad

  // 수면
  final Duration? sleep;        // 어젯밤 총 수면 or 평균 수면
  final ReportGrade sleepGrade;

  // 심박/HRV (선택)
  final int? hrAvg;
  final int? hrvRmssd;
  final ReportGrade hrGrade;

  // 혈압
  final int? bpSys;
  final int? bpDia;
  final ReportGrade bpGrade;

  // 혈당
  final int? glucoseFasting;
  final int? glucosePost;
  final ReportGrade glucoseGrade;

  // 체중
  final double? weight;
  final double? weightDeltaKg;
  final ReportGrade weightGrade;

  // 잠혈(최근 결과)
  final DateTime? occultBloodDate;
  final bool? occultBloodPositive; // true/false/null(미기록)

  const HealthReportData({
    required this.generatedAt,
    required this.subjectName,
    required this.rangeLabel,
    this.steps,
    this.stepsGrade = ReportGrade.unknown,
    this.sleep,
    this.sleepGrade = ReportGrade.unknown,
    this.hrAvg,
    this.hrvRmssd,
    this.hrGrade = ReportGrade.unknown,
    this.bpSys,
    this.bpDia,
    this.bpGrade = ReportGrade.unknown,
    this.glucoseFasting,
    this.glucosePost,
    this.glucoseGrade = ReportGrade.unknown,
    this.weight,
    this.weightDeltaKg,
    this.weightGrade = ReportGrade.unknown,
    this.occultBloodDate,
    this.occultBloodPositive,
  });
}

class ReportColors {
  static const good = Color(0xFF2E7D32);   // 초록
  static const warn = Color(0xFFF57C00);   // 주황
  static const bad  = Color(0xFFC62828);   // 빨강
  static const ink  = Color(0xFF222222);
  static const sub  = Color(0xFF666666);
}

Color gradeColor(ReportGrade g) {
  switch (g) {
    case ReportGrade.good: return ReportColors.good;
    case ReportGrade.warn: return ReportColors.warn;
    case ReportGrade.bad:  return ReportColors.bad;
    case ReportGrade.unknown: default: return ReportColors.sub;
  }
}

String fmtSteps(int? v) => v == null ? '—' : _thousands(v);
String fmtSleep(Duration? d) {
  if (d == null) return '—';
  final h = d.inMinutes ~/ 60;
  final m = d.inMinutes % 60;
  return '${h}시간 ${m}분';
}
String fmtWeight(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} kg';
String fmtDelta(double? v) {
  if (v == null || v == 0) return '변화 없음';
  return '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} kg';
}
String fmtBloodPressure(int? sys, int? dia) =>
    (sys == null || dia == null) ? '—' : '$sys/$dia mmHg';
String fmtGlucose(int? f, int? p) {
  final a = f == null ? '—' : '$f';
  final b = p == null ? '—' : '$p';
  return '식전 $a / 식후 $b mg/dL';
}
String fmtOccult(DateTime? dt, bool? pos) {
  final date = (dt == null) ? '기록 없음' : '${dt.year}.${_2(dt.month)}.${_2(dt.day)}';
  if (pos == null) return '$date • 결과: 미기록';
  return '$date • 결과: ${pos ? '잠혈(+)' : '잠혈(-)'}';
}

String _thousands(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idx = s.length - i;
    buf.write(s[i]);
    if (idx > 1 && idx % 3 == 1) buf.write(',');
  }
  return buf.toString();
}
String _2(int x) => x.toString().padLeft(2, '0');
