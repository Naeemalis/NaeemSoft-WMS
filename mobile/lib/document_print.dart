import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> openDocumentPrint(
  BuildContext context, {
  required Future<dynamic> Function() loadDocument,
  required String fileName,
  required String pageTitle,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DocumentPrintPage(
        loadDocument: loadDocument,
        fileName: fileName,
        pageTitle: pageTitle,
      ),
    ),
  );
}

class DocumentPrintPage extends StatefulWidget {
  const DocumentPrintPage({
    required this.loadDocument,
    required this.fileName,
    required this.pageTitle,
    super.key,
  });

  final Future<dynamic> Function() loadDocument;
  final String fileName;
  final String pageTitle;

  @override
  State<DocumentPrintPage> createState() => _DocumentPrintPageState();
}

class _DocumentPrintPageState extends State<DocumentPrintPage> {
  late Future<dynamic> _document;

  @override
  void initState() {
    super.initState();
    _document = widget.loadDocument();
  }

  String _statusLabel(Object? status) => switch (status?.toString()) {
        'draft' => 'مسودة - غير معتمدة',
        'pending_approval' => 'بانتظار الاعتماد - غير نهائية',
        'approved' => 'معتمدة',
        'cancelled' => 'ملغاة',
        _ => status?.toString() ?? '-',
      };

  Future<Uint8List> _buildPdf(PdfPageFormat format, Map<String, dynamic> data) async {
    final header = Map<String, dynamic>.from(data['document'] as Map);
    final items = (data['items'] as List).cast<Map>();
    final font = await PdfGoogleFonts.notoSansArabicRegular();
    final boldFont = await PdfGoogleFonts.notoSansArabicBold();
    final pdf = pw.Document();
    final isReceipt = header.containsKey('receipt_number');
    final number = header[isReceipt ? 'receipt_number' : 'issue_number']?.toString() ?? '';
    final date = header[isReceipt ? 'receipt_date' : 'issue_date']?.toString() ?? '';
    final amountKey = isReceipt ? 'unit_cost' : 'unit_price';
    final amountLabel = isReceipt ? 'تكلفة الوحدة' : 'سعر الوحدة';
    final currency = header['currency_code']?.toString() ?? '';
    final total = header['total']?.toString() ?? '0';

    pw.Widget cell(String value, {bool bold = false, pw.TextAlign align = pw.TextAlign.right}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          value,
          textAlign: align,
          style: pw.TextStyle(font: bold ? boldFont : font, fontSize: 9),
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text('NaeemSoft WMS', style: pw.TextStyle(font: boldFont, fontSize: 18)),
          ),
          pw.SizedBox(height: 5),
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text(widget.pageTitle, style: pw.TextStyle(font: boldFont, fontSize: 15)),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text('رقم المستند: $number', style: pw.TextStyle(font: boldFont)),
                pw.Text('التاريخ: $date', style: pw.TextStyle(font: font)),
                pw.Text('الجهة: ${header['party_name'] ?? '-'}', style: pw.TextStyle(font: font)),
                pw.Text('الفرع: ${header['branch_name'] ?? '-'}    المستودع: ${header['warehouse_name'] ?? '-'}', style: pw.TextStyle(font: font)),
                pw.Text('الحالة: ${_statusLabel(header['status'])}', style: pw.TextStyle(font: boldFont)),
                pw.Text('أنشأه: ${header['created_by_name'] ?? '-'}', style: pw.TextStyle(font: font)),
                if ((header['notes'] ?? '').toString().isNotEmpty)
                  pw.Text('ملاحظات: ${header['notes']}', style: pw.TextStyle(font: font)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .5),
            columnWidths: {
              0: const pw.FlexColumnWidth(.7),
              1: const pw.FlexColumnWidth(2.8),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(.9),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  cell('#', bold: true),
                  cell('الصنف', bold: true),
                  cell('الوحدة', bold: true),
                  cell('الكمية', bold: true),
                  cell(amountLabel, bold: true),
                  cell('الإجمالي', bold: true),
                ],
              ),
              ...items.map((item) => pw.TableRow(children: [
                    cell('${item['line_number'] ?? ''}'),
                    cell('${item['product_name'] ?? ''}'),
                    cell('${item['unit_name'] ?? ''}'),
                    cell('${item['quantity'] ?? ''}'),
                    cell('${item[amountKey] ?? ''}'),
                    cell('${item['line_total'] ?? ''}'),
                  ])),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text('الإجمالي: $total $currency', style: pw.TextStyle(font: boldFont, fontSize: 13)),
          ),
          pw.SizedBox(height: 32),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('توقيع المستلم: ______________', style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text('توقيع المسؤول: ______________', style: pw.TextStyle(font: font, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.pageTitle)),
        body: FutureBuilder<dynamic>(
          future: _document,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('تعذر تحميل المستند: ${snapshot.error}'),
              ));
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final data = Map<String, dynamic>.from(snapshot.data as Map);
            return PdfPreview(
              canChangeOrientation: false,
              canChangePageFormat: true,
              allowPrinting: true,
              allowSharing: true,
              pdfFileName: widget.fileName,
              build: (format) => _buildPdf(format, data),
            );
          },
        ),
      );
}
