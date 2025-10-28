// lib/report/health_report_models.dart
import 'package:intl/intl.dart';

class HealthRecord {
  final String type;
  final String unit;
  final String value;
  final DateTime start;
  final DateTime end;
  final String source;

  HealthRecord({
    required this.type,
    required this.unit,
    required this.value,
    required this.start,
    required this.end,
    required this.source,
  });

  static String toCsv(List<HealthRecord> rows) {
    final b = StringBuffer();
    b.writeln('type,unit,value,start,end,source');
    final df = DateFormat("yyyy-MM-dd HH:mm:ss");
    for (final r in rows) {
      final line = [
        _csv(r.type),
        _csv(r.unit),
        _csv(r.value),
        _csv(df.format(r.start)),
        _csv(df.format(r.end)),
        _csv(r.source),
      ].join(',');
      b.writeln(line);
    }
    return b.toString();
  }

  static String _csv(String s) {
    final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
    if (!needsQuote) return s;
    return '"${s.replaceAll('"', '""')}"';
  }
}

class HealthReportData {
  final DateTime generatedAt;
  final String subjectName;
  final String rangeLabel;
  final List<HealthRecord> records;

  HealthReportData({
    required this.generatedAt,
    required this.subjectName,
    required this.rangeLabel,
    required this.records,
  });
}
