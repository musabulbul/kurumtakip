import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

class ExportUtils {
  static String _timestamp() =>
      DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  /// Built-in PDF fontları Türkçe karakterleri desteklemez;
  /// PDF çıktısında Latin karşılıklarına dönüştürülür.
  static String _tr(String text) => text
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'G')
      .replaceAll('ş', 's')
      .replaceAll('Ş', 'S')
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'I')
      .replaceAll('ö', 'o')
      .replaceAll('Ö', 'O')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'U')
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'C');

  static Future<void> shareExcel({
    required BuildContext context,
    required String fileBaseName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow(List<dynamic>.from(headers));
      for (final row in rows) {
        sheet.appendRow(List<dynamic>.from(row));
      }

      if (kIsWeb) {
        final bytes = excel.encode();
        if (bytes == null) return;
        final blob = html.Blob(
          [bytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', '${fileBaseName}_${_timestamp()}.xlsx')
          ..click();
        html.Url.revokeObjectUrl(url);
        return;
      }

      final bytes = excel.encode();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/${fileBaseName}_${_timestamp()}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel oluşturulamadı: $e')),
        );
      }
    }
  }

  static Future<void> sharePdf({
    required BuildContext context,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    try {
      final pdf = pw.Document();
      final safeTitle = _tr(title);
      final safeHeaders = headers.map(_tr).toList();
      final safeRows = rows.map((r) => r.map(_tr).toList()).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            pw.Text(
              safeTitle,
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: safeHeaders,
              data: safeRows,
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      );

      final bytes = await pdf.save();

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute(
              'download',
              '${_tr(title).replaceAll(' ', '_')}_${_timestamp()}.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${_tr(title).replaceAll(' ', '_')}_${_timestamp()}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulamadı: $e')),
        );
      }
    }
  }
}
