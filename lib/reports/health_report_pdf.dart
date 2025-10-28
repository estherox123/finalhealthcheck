// lib/report/health_report_pdf.dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'health_report_models.dart';

class HealthReportPdf {
  // 폰트 캐시(한 번만 로드)
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static Future<void> _ensureFontsLoaded() async {
    if (_fontRegular != null && _fontBold != null) return;

    final regularData = await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf');

    _fontRegular = pw.Font.ttf(regularData);
    _fontBold = pw.Font.ttf(boldData);
  }

  static Future<List<int>> build(HealthReportData data) async {
    await _ensureFontsLoaded();

    final theme = pw.ThemeData.withFont(
      base: _fontRegular!,
      bold: _fontBold!,
    );

    final pdf = pw.Document(theme: theme);
    final df = DateFormat("yyyy-MM-dd HH:mm");

    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.all(28),
        ),
        header: (c) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '헬스 리포트',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              data.rangeLabel,
              style: const pw.TextStyle(color: PdfColors.grey700),
            ),
          ],
        ),
        footer: (c) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '생성: ${df.format(data.generatedAt)}  •  Page ${c.pageNumber}/${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
        build: (c) => [
          pw.SizedBox(height: 8),
          _infoBlock(data, df),
          pw.SizedBox(height: 12),
          _table(data, df),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _infoBlock(HealthReportData d, DateFormat df) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.indigo),
        color: PdfColors.indigo50,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '피검자: ${d.subjectName}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('범위: ${d.rangeLabel}', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 2),
          pw.Text('항목 수: ${d.records.length}', style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  static pw.Widget _table(HealthReportData d, DateFormat df) {
    final headers = ['Type', 'Value', 'Unit', 'Start', 'End', 'Source'];

    final rows = d.records.map((r) {
      return [
        r.type,
        r.value,
        r.unit,
        df.format(r.start),
        df.format(r.end),
        r.source,
      ];
    }).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black),
      cellStyle: const pw.TextStyle(fontSize: 10),
      cellAlignment: pw.Alignment.centerLeft,
      headerPadding: const pw.EdgeInsets.all(6),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      border: null,
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: .5),
        ),
      ),
    );
  }
}
