import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../dicom/dicom_image_converter.dart';
import '../dicom/dicom_parser.dart';
import '../models/patient.dart';
import 'dental_repository.dart';

/// The DICOM shipped inside the app, imported onto a sample patient the first
/// time Stom runs so a fresh install already shows a real x-ray instead of an
/// empty image list.
const String kSampleXrayAsset = 'assets/sample/sample_xray.dcm';

/// Which sample patient and tooth the x-ray lands on: Anna Petrosyan's tooth
/// 14, which the seeded notes describe as root-canal treated.
const String _patientFirstName = 'Anna';
const String _patientLastName = 'Petrosyan';
const int _toothNumber = 14;

/// Imports [kSampleXrayAsset] for the sample patient, unless that tooth
/// already has an image (so it is never imported twice, and never touches a
/// real practice's data).
///
/// Best-effort like the rest of the sample data: any failure is swallowed, as
/// a missing demo x-ray must never stop the app from starting.
Future<void> seedSampleXrayIfMissing(DentalRepository repository) async {
  // The web build has no writable directory for the rendered image.
  if (kIsWeb) return;
  try {
    final patients = await repository.getPatients();
    Patient? target;
    for (final patient in patients) {
      if (patient.firstName == _patientFirstName &&
          patient.lastName == _patientLastName) {
        target = patient;
        break;
      }
    }
    final patientId = target?.id;
    if (patientId == null) return;

    final existing = await repository.getImages(patientId, _toothNumber);
    if (existing.isNotEmpty) return;

    final data = await rootBundle.load(kSampleXrayAsset);
    final dicomBytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final dataset = const DicomParser().parse(dicomBytes);
    final rendered = await const DicomImageConverter().convert(dataset);

    final docsDir = await getApplicationDocumentsDirectory();
    final xraysDir = Directory(p.join(docsDir.path, 'xrays'));
    if (!await xraysDir.exists()) {
      await xraysDir.create(recursive: true);
    }
    final baseName = 'sample_p${patientId}_t$_toothNumber';
    final displayPath = p.join(xraysDir.path, '$baseName.${rendered.extension}');
    final originalPath = p.join(xraysDir.path, '$baseName.dcm');
    await File(displayPath).writeAsBytes(rendered.bytes);
    await File(originalPath).writeAsBytes(dicomBytes);

    await repository.addImage(
      patientId,
      _toothNumber,
      displayPath,
      originalDicomPath: originalPath,
    );
  } catch (_) {
    // Demo data only - leave the app running without it.
  }
}
