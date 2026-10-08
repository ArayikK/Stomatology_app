import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../dicom/dicom_image_converter.dart';
import '../dicom/dicom_parser.dart';

/// Where imported x-rays live inside the app's own storage.
Future<Directory> xraysDirectory() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docsDir.path, 'xrays'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// How many slices one import may bring in. A full CBCT export can be
/// thousands of images; this is enough for a real scan while still keeping
/// the phone's storage and the import time sane.
const int kMaxSlicesPerImport = 800;

/// The file name of one slice inside a CBCT series folder. Zero-padded so
/// the folder also sorts correctly when opened outside the app.
String sliceFileName(int index) => 'slice_${index.toString().padLeft(4, '0')}.png';

String slicePath(String seriesDir, int index) => p.join(seriesDir, sliceFileName(index));

/// One imported DICOM: the displayable image, the original file kept beside
/// it, and the scale read out of the file.
class ImportedDicom {
  const ImportedDicom({
    required this.displayPath,
    required this.originalPath,
    this.pixelSpacingMm,
  });

  final String displayPath;
  final String originalPath;
  final double? pixelSpacingMm;
}

/// Renders one DICOM to a PNG next to a copy of the original.
Future<ImportedDicom> importDicomBytes({
  required Uint8List bytes,
  required String baseName,
}) async {
  final dataset = const DicomParser().parse(bytes);
  final rendered = await const DicomImageConverter().convert(dataset);
  final dir = await xraysDirectory();
  final displayPath = p.join(dir.path, '$baseName.${rendered.extension}');
  final originalPath = p.join(dir.path, '$baseName.dcm');
  await File(displayPath).writeAsBytes(rendered.bytes);
  await File(originalPath).writeAsBytes(bytes);
  return ImportedDicom(
    displayPath: displayPath,
    originalPath: originalPath,
    pixelSpacingMm: dataset.info.pixelSpacingMm,
  );
}

/// A CBCT series: every slice rendered into one folder, ordered the way the
/// scanner numbered them.
class ImportedSeries {
  const ImportedSeries({
    required this.seriesDir,
    required this.sliceCount,
    required this.firstSlicePath,
    required this.skipped,
    this.sliceNames = const [],
    this.pixelSpacingMm,
    this.singleOriginalPath,
  });

  final String seriesDir;
  final int sliceCount;

  /// The slice the app opens on: the middle of the stack, which is where the
  /// anatomy of interest usually is.
  final String firstSlicePath;

  /// How many files couldn't be decoded and were left out.
  final int skipped;

  /// The source file names that ended up as slices, in slice order.
  final List<String> sliceNames;

  final double? pixelSpacingMm;

  /// Set only when the import turned out to hold a single image rather than
  /// a stack: the original .dcm, kept so it can still be exported.
  final String? singleOriginalPath;

  bool get isSingleImage => sliceCount == 1;
}

/// One file waiting to be rendered: its name, and a way to get its bytes
/// only when they are actually needed. The callback matters for ZIPs, where
/// holding every slice in memory at once would run a phone out of RAM.
typedef _SliceSource = ({String name, Future<Uint8List?> Function() read});

/// Renders a stack of DICOM slices into one folder.
///
/// Slices are ordered by Instance Number when the files carry one, falling
/// back to the file name. [onProgress] is called after each slice so the UI
/// can show how far along it is; [cap] stops runaway imports - a full CBCT
/// export can be thousands of slices, which no phone should try to render in
/// one go.
Future<ImportedSeries> _renderSlices({
  required List<_SliceSource> sources,
  required String baseName,
  void Function(int done, int total)? onProgress,
  required int cap,
}) async {
  final root = await xraysDirectory();
  final seriesDir = Directory(p.join(root.path, baseName));
  if (!await seriesDir.exists()) await seriesDir.create(recursive: true);

  const converter = DicomImageConverter();
  final rendered = <({int? instanceNumber, String name, File file})>[];
  var skipped = 0;
  double? pixelSpacingMm;
  var seq = 0;

  // One pass, one decode per file: each slice is rendered straight to disk
  // under a temporary name and the bytes are dropped again, so memory stays
  // flat no matter how many slices there are. The files are put in their
  // real order afterwards, which is only renaming.
  for (final source in sources) {
    if (rendered.length >= cap) {
      skipped++;
      continue;
    }
    Uint8List? bytes;
    try {
      bytes = await source.read();
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || !looksLikeDicom(bytes)) {
      skipped++;
      continue;
    }
    try {
      final dataset = const DicomParser().parse(bytes);
      final image = await converter.convert(dataset);
      final file = File(p.join(seriesDir.path, 'tmp_${seq++}.png'));
      await file.writeAsBytes(image.bytes);
      rendered.add((
        instanceNumber: dataset.info.instanceNumber,
        name: source.name,
        file: file,
      ));
      pixelSpacingMm ??= dataset.info.pixelSpacingMm;
      onProgress?.call(rendered.length, sources.length);
      // Hand the frame back between slices, so the progress dialog actually
      // repaints instead of the app looking frozen for a minute.
      await Future<void>.delayed(Duration.zero);
    } catch (_) {
      skipped++;
    }
  }

  if (rendered.isEmpty) {
    if (await seriesDir.exists()) await seriesDir.delete(recursive: true);
    throw const DicomParseException(
      'None of the selected files could be read as DICOM images.',
    );
  }

  rendered.sort((a, b) {
    final an = a.instanceNumber;
    final bn = b.instanceNumber;
    if (an != null && bn != null && an != bn) return an.compareTo(bn);
    return a.name.compareTo(b.name);
  });

  for (var i = 0; i < rendered.length; i++) {
    await rendered[i].file.rename(slicePath(seriesDir.path, i));
  }

  return ImportedSeries(
    seriesDir: seriesDir.path,
    sliceCount: rendered.length,
    firstSlicePath: slicePath(seriesDir.path, rendered.length ~/ 2),
    skipped: skipped,
    sliceNames: [for (final slice in rendered) slice.name],
    pixelSpacingMm: pixelSpacingMm,
  );
}

/// Renders a stack of DICOM files the dentist picked one by one.
Future<ImportedSeries> importDicomSeries({
  required List<({String name, Uint8List bytes})> files,
  required String baseName,
  void Function(int done, int total)? onProgress,
  int cap = kMaxSlicesPerImport,
}) {
  return _renderSlices(
    sources: [
      for (final file in files) (name: file.name, read: () async => file.bytes),
    ],
    baseName: baseName,
    onProgress: onProgress,
    cap: cap,
  );
}

/// Imports a whole CBCT scan out of one .zip - what scanners and PACS
/// actually hand over, and far less work than selecting hundreds of files by
/// hand.
///
/// The archive is read straight off disk rather than loaded into memory, and
/// each slice's bytes are released as soon as it is rendered, so a scan of
/// several hundred megabytes imports on an ordinary phone.
Future<ImportedSeries> importDicomZip({
  required String zipPath,
  required String baseName,
  void Function(int done, int total)? onProgress,
  int cap = kMaxSlicesPerImport,
}) async {
  final input = InputFileStream(zipPath);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (e) {
      throw const DicomParseException(
        'This file could not be opened as a .zip archive.',
      );
    }

    final entries = archive.files.where(_isCandidateEntry).toList();
    if (entries.isEmpty) {
      throw const DicomParseException(
        'No DICOM files were found inside this archive.',
      );
    }

    // Big archives drop each slice's decompressed bytes as soon as it is
    // rendered, or a whole scan would still end up in memory. Small ones
    // keep theirs, so the original file can be read back below.
    final releaseAfterRead = entries.length > 8;
    final series = await _renderSlices(
      sources: [
        for (final entry in entries)
          (
            name: p.basename(entry.name),
            read: () async {
              final bytes = entry.readBytes();
              if (releaseAfterRead) entry.clear();
              return bytes;
            },
          ),
      ],
      baseName: baseName,
      onProgress: onProgress,
      cap: cap,
    );

    // A "series" of one is just a single x-ray that happened to be zipped:
    // keep its original file too, the way a plain .dcm import does.
    if (series.sliceCount == 1 && series.sliceNames.isNotEmpty) {
      final name = series.sliceNames.single;
      final entry = entries
          .where((e) => p.basename(e.name) == name)
          .firstOrNull;
      final bytes = entry?.readBytes();
      if (bytes != null) {
        final originalPath = p.join(series.seriesDir, 'original.dcm');
        await File(originalPath).writeAsBytes(bytes);
        entry!.clear();
        return ImportedSeries(
          seriesDir: series.seriesDir,
          sliceCount: 1,
          firstSlicePath: series.firstSlicePath,
          skipped: series.skipped,
          sliceNames: series.sliceNames,
          pixelSpacingMm: series.pixelSpacingMm,
          singleOriginalPath: originalPath,
        );
      }
    }
    return series;
  } finally {
    await input.close();
  }
}

/// Files inside a ZIP worth trying to parse. Scanners are inconsistent about
/// extensions - plenty of exports have none at all - so anything that isn't
/// obviously junk is tried, and the DICM check does the real filtering.
bool _isCandidateEntry(ArchiveFile entry) {
  if (!entry.isFile || entry.size < 132) return false;
  final name = entry.name.replaceAll('\\', '/');
  final base = p.basename(name);
  // Folder metadata that macOS and Windows sprinkle into archives.
  if (name.startsWith('__MACOSX/') || base.startsWith('.') || base == 'Thumbs.db') {
    return false;
  }
  if (base.toUpperCase() == 'DICOMDIR') return false;
  const skip = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.txt', '.pdf', '.xml',
    '.html', '.htm', '.json', '.exe', '.dll', '.zip', '.mp4', '.avi', '.doc', '.docx'};
  return !skip.contains(p.extension(base).toLowerCase());
}

/// True when the bytes carry the "DICM" marker of a DICOM Part 10 file.
bool looksLikeDicom(Uint8List bytes) {
  if (bytes.length < 132) return false;
  return bytes[128] == 0x44 && bytes[129] == 0x49 && bytes[130] == 0x43 && bytes[131] == 0x4D;
}
