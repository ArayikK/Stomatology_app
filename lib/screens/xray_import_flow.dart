import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../data/xray_import.dart';
import '../dicom/dicom_parser.dart';

/// Where an x-ray can come from. The last three are all DICOM; they differ
/// only in how much is being brought in at once.
enum XraySource {
  gallery,
  camera,

  /// A single .dcm file.
  dicom,

  /// A .zip straight off the scanner or PACS - the whole scan in one file.
  dicomZip,

  /// Several .dcm files picked by hand.
  dicomSeries,
}

/// The "add an image" sheet, shared by the tooth screen and the patient's
/// x-ray tab so both offer exactly the same sources.
Future<XraySource?> showXraySourceSheet(BuildContext context) {
  return showModalBottomSheet<XraySource>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(context).pop(XraySource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.of(context).pop(XraySource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('Import DICOM (.dcm)'),
            subtitle: const Text('X-ray export from a dental sensor/PACS'),
            onTap: () => Navigator.of(context).pop(XraySource.dicom),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Import CBCT from .zip'),
            subtitle: const Text('A whole scan in one archive - no picking files'),
            onTap: () => Navigator.of(context).pop(XraySource.dicomZip),
          ),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Import CBCT slices'),
            subtitle: const Text('Select the .dcm files of a scan by hand'),
            onTap: () => Navigator.of(context).pop(XraySource.dicomSeries),
          ),
        ],
      ),
    ),
  );
}

/// Runs one import from start to finish: picking the file(s), decoding,
/// saving into the app's storage, writing the database row, and showing
/// progress or a readable error.
///
/// [toothNumber] is `kGeneralToothNumber` (0) for images that belong to the
/// patient as a whole rather than to one tooth.
///
/// Returns true when something was actually added, so the caller can reload.
Future<bool> runXrayImport({
  required BuildContext context,
  required DentalRepository repository,
  required BackendSyncService syncService,
  required int patientId,
  required int toothNumber,
  required XraySource source,
}) async {
  // Captured before the first await: the picker takes the user out of the
  // app, and the screen that started the import may be gone by the time it
  // comes back.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    final added = switch (source) {
      XraySource.gallery => await _importPhoto(repository, patientId, toothNumber, ImageSource.gallery),
      XraySource.camera => await _importPhoto(repository, patientId, toothNumber, ImageSource.camera),
      XraySource.dicom => await _importSingleDicom(repository, patientId, toothNumber),
      XraySource.dicomZip => await _importZip(navigator, repository, patientId, toothNumber, messenger),
      XraySource.dicomSeries => await _importPickedSlices(navigator, repository, patientId, toothNumber, messenger),
    };
    if (added) unawaited(syncService.pushAll());
    return added;
  } on DicomParseException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not import this file: $e')));
    return false;
  }
}

String _baseName(int patientId, int toothNumber, {String prefix = ''}) {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  return '${prefix}p${patientId}_t${toothNumber}_$stamp';
}

Future<bool> _importPhoto(
  DentalRepository repository,
  int patientId,
  int toothNumber,
  ImageSource source,
) async {
  final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
  if (picked == null) return false;
  final dir = await xraysDirectory();
  final savedPath = p.join(
    dir.path,
    '${_baseName(patientId, toothNumber)}${p.extension(picked.path)}',
  );
  await File(picked.path).copy(savedPath);
  await repository.addImage(patientId, toothNumber, savedPath);
  return true;
}

Future<bool> _importSingleDicom(
  DentalRepository repository,
  int patientId,
  int toothNumber,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['dcm'],
    withData: true,
  );
  final picked = result?.files.single;
  if (picked?.bytes == null) return false;

  final imported = await importDicomBytes(
    bytes: picked!.bytes!,
    baseName: _baseName(patientId, toothNumber),
  );
  await repository.addImage(
    patientId,
    toothNumber,
    imported.displayPath,
    originalDicomPath: imported.originalPath,
    pixelSpacingMm: imported.pixelSpacingMm,
  );
  return true;
}

Future<bool> _importZip(
  NavigatorState navigator,
  DentalRepository repository,
  int patientId,
  int toothNumber,
  ScaffoldMessengerState messenger,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
    // Deliberately not withData: a CBCT archive can be hundreds of
    // megabytes, and it is read off disk a slice at a time instead.
    withData: false,
  );
  final path = result?.files.single.path;
  if (path == null) return false;

  return _withProgress(
    navigator,
    title: 'Importing scan',
    run: (progress) async {
      final series = await importDicomZip(
        zipPath: path,
        baseName: _baseName(patientId, toothNumber, prefix: 'series_'),
        onProgress: (done, total) => progress.value = 'Slice $done of $total',
      );
      await _saveSeries(repository, patientId, toothNumber, series);
      _reportSkipped(messenger, series);
      return true;
    },
  );
}

Future<bool> _importPickedSlices(
  NavigatorState navigator,
  DentalRepository repository,
  int patientId,
  int toothNumber,
  ScaffoldMessengerState messenger,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['dcm'],
    allowMultiple: true,
    withData: true,
  );
  final picked = result?.files.where((f) => f.bytes != null).toList() ?? [];
  if (picked.isEmpty) return false;

  if (picked.length == 1) {
    final imported = await importDicomBytes(
      bytes: picked.first.bytes!,
      baseName: _baseName(patientId, toothNumber),
    );
    await repository.addImage(
      patientId,
      toothNumber,
      imported.displayPath,
      originalDicomPath: imported.originalPath,
      pixelSpacingMm: imported.pixelSpacingMm,
    );
    return true;
  }

  return _withProgress(
    navigator,
    title: 'Importing slices',
    run: (progress) async {
      final series = await importDicomSeries(
        files: [for (final file in picked) (name: file.name, bytes: file.bytes!)],
        baseName: _baseName(patientId, toothNumber, prefix: 'series_'),
        onProgress: (done, total) => progress.value = 'Slice $done of $total',
      );
      await _saveSeries(repository, patientId, toothNumber, series);
      _reportSkipped(messenger, series);
      return true;
    },
  );
}

Future<void> _saveSeries(
  DentalRepository repository,
  int patientId,
  int toothNumber,
  ImportedSeries series,
) async {
  await repository.addImage(
    patientId,
    toothNumber,
    series.firstSlicePath,
    originalDicomPath: series.singleOriginalPath,
    pixelSpacingMm: series.pixelSpacingMm,
    // A stack of one is stored as a plain image, not as a series with a
    // pointless one-position slider.
    seriesDir: series.isSingleImage ? null : series.seriesDir,
    sliceCount: series.isSingleImage ? null : series.sliceCount,
  );
}

void _reportSkipped(ScaffoldMessengerState messenger, ImportedSeries series) {
  if (series.skipped == 0) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '${series.sliceCount} slices imported, ${series.skipped} skipped '
        '- either not readable, or past the $kMaxSlicesPerImport-slice limit.',
      ),
    ),
  );
}

/// Shows a modal "working..." dialog with a live line of progress, and makes
/// sure it is closed again whether the import succeeds or throws.
Future<bool> _withProgress(
  NavigatorState navigator, {
  required String title,
  required Future<bool> Function(ValueNotifier<String> progress) run,
}) async {
  final progress = ValueNotifier<String>('Reading the archive…');
  // The screen may have been left while the file picker was open; then there
  // is nothing to show a dialog on, and the import just runs quietly.
  var dialogOpen = navigator.mounted;

  if (dialogOpen) {
    unawaited(
      showDialog<void>(
        context: navigator.context,
      barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: progress,
                    builder: (context, value, _) => Text(value),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).then((_) => dialogOpen = false),
    );
  }

  try {
    return await run(progress);
  } finally {
    if (dialogOpen && navigator.mounted) navigator.pop();
    progress.dispose();
  }
}
