import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/annotation_shape.dart';
import '../models/image_view_settings.dart';
import '../models/patient.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';
import '../widgets/annotated_image.dart';

/// Flattens an image together with its brightness/contrast setting and its
/// annotations into a single PNG - what a report or a shared file has to
/// contain, since the annotations live in the database, not in the file.
Future<Uint8List?> renderAnnotatedPng({
  required File file,
  required List<AnnotationShape> shapes,
  required ImageViewSettings settings,
  double? mmPerPixel,
  int maxWidth = 1400,
}) async {
  try {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final scale = image.width > maxWidth ? maxWidth / image.width : 1.0;
    final width = (image.width * scale).round();
    final height = (image.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..colorFilter = ColorFilter.matrix(settings.colorMatrix()),
    );
    AnnotationPainter(
      shapes: shapes,
      scale: ImageScale(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        mmPerPixel: mmPerPixel,
      ),
      // The report is printed at a larger size than the phone screen.
      strokeWidth: 3 * (width / 600).clamp(1.0, 3.0),
      fontSize: 12 * (width / 600).clamp(1.0, 3.0),
    ).paint(canvas, Size(width.toDouble(), height.toDouble()));

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    rendered.dispose();
    picture.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// One image as it goes into the report: already flattened, with the caption
/// the page prints under it.
class ReportImage {
  const ReportImage({required this.png, required this.caption});
  final Uint8List png;
  final String caption;
}

/// Builds the printable/shareable PDF: who the patient is, which tooth, the
/// x-rays with their markings, and the written history. Meant for handing to
/// the patient, a colleague, or an insurer.
Future<Uint8List> buildToothReportPdf({
  required Patient patient,
  required int toothNumber,
  required List<ReportImage> images,
  required List<ToothNote> notes,
  String? clinicName,
}) async {
  final doc = pw.Document(theme: await _unicodeTheme());
  final printed = _formatDate(DateTime.now());

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        margin: const pw.EdgeInsets.only(bottom: 16),
        child: pw.Text(
          clinicName ?? 'Dental report',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.Text(
          patient.fullName,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Tooth $toothNumber  ·  printed $printed',
          style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        if (patient.hasAllergies) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.red50,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'Allergies: ${patient.allergies}',
              style: pw.TextStyle(fontSize: 11, color: PdfColors.red900),
            ),
          ),
        ],
        pw.SizedBox(height: 20),
        if (images.isNotEmpty) ...[
          pw.Text(
            'Images',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          for (final image in images) ...[
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(image.png),
                height: 260,
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                image.caption,
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
        ],
        if (notes.isNotEmpty) ...[
          pw.Text(
            'History',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          for (final note in notes)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        note.category.label,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        _formatDate(note.updatedAt),
                        style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(note.text, style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
        ],
        if (images.isEmpty && notes.isEmpty)
          pw.Text(
            'Nothing recorded for this tooth yet.',
            style: const pw.TextStyle(fontSize: 11),
          ),
      ],
    ),
  );

  return doc.save();
}

/// The PDF fonts that can actually print Armenian and Cyrillic names - the
/// library's built-in Helvetica cannot, and would silently drop those
/// letters from a printed report.
///
/// The faces are bundled with the app rather than downloaded, so a report
/// prints correctly with no network at all. Loaded once and kept.
pw.ThemeData? _cachedTheme;

Future<pw.ThemeData?> _unicodeTheme() async {
  if (_cachedTheme != null) return _cachedTheme;
  try {
    final base = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final armenian = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArmenian-Regular.ttf'),
    );
    return _cachedTheme = pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [armenian],
    );
  } catch (_) {
    // Worst case the report still prints, just without the extra scripts.
    return null;
  }
}

/// The caption printed under one image in the report.
String describeReportImage(ToothImage image) {
  final parts = <String>[_formatDate(image.createdAt)];
  if (image.originalDicomPath != null) parts.add('DICOM');
  if (image.isSeries) parts.add('${image.sliceCount} slices');
  if (image.role != null) {
    parts.add(image.role == ImageRole.before ? 'before' : 'after');
  }
  if (image.isCalibrated) {
    parts.add('${image.pixelSpacingMm!.toStringAsFixed(3)} mm/px');
  }
  return parts.join('  ·  ');
}

String _formatDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d.$m.${date.year}';
}
