import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../reports/report_models.dart';
import '../reports/pdf_report_generator.dart';

class ReportPreviewPage extends StatelessWidget {
  final HealthReportData data;
  const ReportPreviewPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('보고서 미리보기 / 내보내기')),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        build: (format) async {
          final gen = PdfReportGenerator(data);
          return await gen.build();
        },
        onPrinted: (context) {},
        onShared: (context) {},
        allowSharing: true,
        pdfFileName:
        'health_report_${data.generatedAt.millisecondsSinceEpoch}.pdf',
      ),
    );
  }
}
