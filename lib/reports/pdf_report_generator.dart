import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'report_models.dart';

class PdfReportGenerator {
  final HealthReportData data;

  PdfReportGenerator(this.data);

  Future<pw.Font> _loadFontRegular() async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'));
  Future<pw.Font> _loadFontBold() async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));

  Future<Uint8List> build() async {
    final regular = await _loadFontRegular();
    final bold = await _loadFontBold();

    final theme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
    );

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          textDirection: pw.TextDirection.ltr,
        ),
        build: (ctx) => [
          _header(),
          pw.SizedBox(height: 10),
          _meta(),
          pw.SizedBox(height: 16),
          _sectionTitle('핵심 요약'),
          _coreGrid(),
          pw.SizedBox(height: 14),
          _sectionTitle('상세 요약'),
          _detailCards(),
          pw.SizedBox(height: 18),
          _footnote(),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _header() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 8,
          height: 24,
          color: PdfColor.fromInt(0xFF3F51B5),
        ),
        pw.SizedBox(width: 8),
        pw.Text('건강 요약 보고서',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  pw.Widget _meta() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('대상: ${data.subjectName}',
            style: const pw.TextStyle(fontSize: 12)),
        pw.Text(
          '생성: ${_yyyyMMddHHmm(data.generatedAt)}',
          style: const pw.TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String t) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 6, bottom: 8),
    child: pw.Text(t,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
  );

  pw.Widget _coreGrid() {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromInt(0x22000000)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.all(12),
      child: pw.GridView(
        crossAxisCount: 2,
        childAspectRatio: 3.6,
        children: [
          _kv('범위', data.rangeLabel),
          _kv('잠혈(최근)', fmtOccult(data.occultBloodDate, data.occultBloodPositive)),
          _kv('걸음수', fmtSteps(data.steps)),
          _kv('수면', fmtSleep(data.sleep)),
        ],
      ),
    );
  }

  pw.Widget _kv(String k, String v) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(k, style: const pw.TextStyle(fontSize: 12)),
      pw.Text(v, style: const pw.TextStyle(fontSize: 12)),
    ],
  );

  pw.Widget _detailCards() {
    return pw.Column(children: [
      _detailRow(
        '활동량',
        fmtSteps(data.steps),
        data.stepsGrade,
        '하루(또는 평균) 걸음수입니다. 무리하지 말고 꾸준히.',
      ),
      pw.SizedBox(height: 8),
      _detailRow(
        '수면',
        fmtSleep(data.sleep),
        data.sleepGrade,
        '최근 수면 시간을 요약했습니다. 추세 위주로 보세요.',
      ),
      pw.SizedBox(height: 8),
      _detailRow(
        '심박/HRV',
        'HR ${data.hrAvg ?? '—'} bpm / HRV ${data.hrvRmssd ?? '—'} ms',
        data.hrGrade,
        '회복상태 판단에 활용됩니다(개인차 큼).',
      ),
      pw.SizedBox(height: 8),
      _detailRow(
        '혈압',
        fmtBloodPressure(data.bpSys, data.bpDia),
        data.bpGrade,
        '최근 혈압입니다. 평소 대비를 중시하세요.',
      ),
      pw.SizedBox(height: 8),
      _detailRow(
        '혈당',
        fmtGlucose(data.glucoseFasting, data.glucosePost),
        data.glucoseGrade,
        '식전/식후 혈당입니다. 저/고혈당 의심 시 지침을 따르세요.',
      ),
      pw.SizedBox(height: 8),
      _detailRow(
        '체중',
        '${fmtWeight(data.weight)}  (${fmtDelta(data.weightDeltaKg)})',
        data.weightGrade,
        '주간 변화 폭을 확인해 주세요.',
      ),
    ]);
  }

  pw.Widget _detailRow(
      String title,
      String value,
      ReportGrade grade,
      String helper,
      ) {
    final color = PdfColor.fromInt(gradeColor(grade).value);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromInt(0x22000000)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 6, height: 36, color: color),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(title,
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text(value,
                        style: pw.TextStyle(
                            fontSize: 13, color: PdfColor.fromInt(0xFF222222))),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(helper,
                    style: pw.TextStyle(
                        fontSize: 10, color: PdfColor.fromInt(0xFF666666))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _footnote() => pw.Text(
    '본 자료는 참고용 요약이며, 의료적 판단은 의료진과 상의하세요.',
    style: pw.TextStyle(
      fontSize: 9,
      color: PdfColor.fromInt(0xFF777777),
    ),
  );

  String _yyyyMMddHHmm(DateTime dt) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${dt.year}.${two(dt.month)}.${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
