// lib/report/health_exporter.dart
import 'package:health/health.dart' as hl;
import 'health_report_models.dart';

/// Health 데이터를 평탄화해서 HealthRecord 리스트로 변환
class HealthExporter {
  final hl.Health health;                         // ← hl.Health (HealthFactory was removed in v10+)
  HealthExporter(this.health);

  Future<List<HealthRecord>> collect({
    required DateTime start,
    required DateTime end,
    required List<hl.HealthDataType> types,      // ← hl. 접두사
  }) async {
    final pts = await health.getHealthDataFromTypes(
      types: types,
      startTime: start,
      endTime: end,
    );

    final out = <HealthRecord>[];
    for (final p in pts) {
      final from = p.dateFrom;
      final to = p.dateTo;
      final value = _stringifyValue(p.value);
      out.add(HealthRecord(
        type: p.type.name,
        unit: p.unit?.name ?? '',
        value: value,
        start: from ?? start,
        end: to ?? from ?? start,
        source: p.sourceId ?? p.sourceName ?? '',
      ));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  // NumericHealthValue 등 다양한 value를 안전하게 string으로
  String _stringifyValue(dynamic v) {
    if (v == null) return '';
    if (v is hl.NumericHealthValue) {            // ← hl. 접두사
      final n = v.numericValue;
      return n?.toString() ?? '';
    }
    return v.toString();
  }
}

