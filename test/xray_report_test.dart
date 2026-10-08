import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stom/models/annotation_shape.dart';
import 'package:stom/models/image_view_settings.dart';
import 'package:stom/models/note_category.dart';
import 'package:stom/models/patient.dart';
import 'package:stom/models/tooth_note.dart';
import 'package:stom/reports/xray_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final patient = Patient(
    id: 1,
    firstName: 'Anna',
    lastName: 'Petrosyan',
    allergies: 'Penicillin',
    createdAt: DateTime(2026, 1, 1),
  );

  test('flattens an image together with its annotations', () async {
    final png = await renderAnnotatedPng(
      file: File('test/fixtures/sample_render_source.png'),
      shapes: const [
        AnnotationShape(
          tool: AnnotationTool.measurement,
          points: [Offset(0.2, 0.2), Offset(0.8, 0.8)],
          colorHex: '#FF3B30',
        ),
      ],
      settings: const ImageViewSettings(contrast: 0.3),
      mmPerPixel: 0.15,
    );

    expect(png, isNotNull);
    // PNG magic number.
    expect(png!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('an unreadable file returns null instead of throwing', () async {
    final png = await renderAnnotatedPng(
      file: File('test/fixtures/does_not_exist.png'),
      shapes: const [],
      settings: ImageViewSettings.none,
    );
    expect(png, isNull);
  });

  test('builds a PDF with the images and the history', () async {
    final png = await renderAnnotatedPng(
      file: File('test/fixtures/sample_render_source.png'),
      shapes: const [],
      settings: ImageViewSettings.none,
    );

    final pdf = await buildToothReportPdf(
      patient: patient,
      toothNumber: 14,
      images: [ReportImage(png: png!, caption: '01.02.2026 · DICOM')],
      notes: [
        ToothNote(
          patientId: 1,
          toothNumber: 14,
          text: 'Root canal completed.',
          category: NoteCategory.rootCanal,
          createdAt: DateTime(2026, 2, 1),
          updatedAt: DateTime(2026, 2, 1),
        ),
      ],
    );

    expect(pdf.length, greaterThan(1000));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  test('prints Armenian and Cyrillic names, not blanks', () async {
    final pdf = await buildToothReportPdf(
      patient: Patient(
        firstName: 'Արամ', // Aram in Armenian
        lastName: 'Петросян', // Petrosyan in Cyrillic
        createdAt: DateTime(2026, 1, 1),
      ),
      toothNumber: 14,
      images: const [],
      notes: const [],
    );

    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    // The bundled Unicode face has to be embedded: with Helvetica alone
    // those letters would come out blank.
    final raw = String.fromCharCodes(pdf);
    expect(raw, contains('NotoSans'));
    expect(raw, isNot(contains('/BaseFont /Helvetica')));
  });

  test('builds a PDF even with nothing recorded yet', () async {
    final pdf = await buildToothReportPdf(
      patient: patient,
      toothNumber: 3,
      images: const [],
      notes: const [],
    );
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });
}
