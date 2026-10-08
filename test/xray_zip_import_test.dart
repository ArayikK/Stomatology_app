import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stom/data/xray_import.dart';
import 'package:stom/dicom/dicom_parser.dart';

void _mockDocumentsDirectory(Directory dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async =>
        call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late Directory workDir;
  late Uint8List slice;

  /// Writes a .zip holding the given entries and returns its path.
  String makeZip(String name, List<ArchiveFile> files) {
    final archive = Archive();
    for (final file in files) {
      archive.add(file);
    }
    final path = p.join(workDir.path, name);
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return path;
  }

  setUp(() {
    docsDir = Directory.systemTemp.createTempSync('stom_zip_docs_');
    workDir = Directory.systemTemp.createTempSync('stom_zip_work_');
    _mockDocumentsDirectory(docsDir);
    slice = File('test/fixtures/sample_uncompressed.dcm').readAsBytesSync();
  });

  tearDown(() {
    for (final dir in [docsDir, workDir]) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('imports a whole scan from one .zip', () async {
    final zip = makeZip('scan.zip', [
      ArchiveFile.bytes('scan/IMG0003.dcm', slice),
      ArchiveFile.bytes('scan/IMG0001.dcm', slice),
      ArchiveFile.bytes('scan/IMG0002.dcm', slice),
    ]);

    final series = await importDicomZip(zipPath: zip, baseName: 'zip_series');

    expect(series.sliceCount, 3);
    expect(series.skipped, 0);
    expect(series.isSingleImage, isFalse);
    for (var i = 0; i < 3; i++) {
      expect(File(slicePath(series.seriesDir, i)).existsSync(), isTrue);
    }
    // No leftovers from the rendering pass.
    final leftovers = Directory(series.seriesDir)
        .listSync()
        .where((e) => p.basename(e.path).startsWith('tmp_'));
    expect(leftovers, isEmpty);
  });

  test('finds slices that have no .dcm extension at all', () async {
    // Plenty of scanners export files named IM_0001 with no extension.
    final zip = makeZip('bare.zip', [
      ArchiveFile.bytes('IM_0001', slice),
      ArchiveFile.bytes('IM_0002', slice),
    ]);

    final series = await importDicomZip(zipPath: zip, baseName: 'zip_bare');
    expect(series.sliceCount, 2);
  });

  test('ignores the junk archives carry around', () async {
    final zip = makeZip('junk.zip', [
      ArchiveFile.bytes('scan/IMG0001.dcm', slice),
      ArchiveFile.bytes('scan/IMG0002.dcm', slice),
      ArchiveFile.string('scan/readme.txt', 'notes about the scan'),
      ArchiveFile.string('__MACOSX/._IMG0001.dcm', 'resource fork rubbish'),
      ArchiveFile.string('scan/DICOMDIR', 'index, not an image'),
      ArchiveFile.string('scan/preview.jpg', 'not really a jpeg'),
    ]);

    final series = await importDicomZip(zipPath: zip, baseName: 'zip_junk');

    // The two real slices came in, and nothing was reported as "skipped",
    // because the junk was never a candidate in the first place.
    expect(series.sliceCount, 2);
    expect(series.skipped, 0);
  });

  test('a zip holding one x-ray is stored as a single image, not a series', () async {
    final zip = makeZip('single.zip', [ArchiveFile.bytes('only.dcm', slice)]);

    final series = await importDicomZip(zipPath: zip, baseName: 'zip_single');

    expect(series.isSingleImage, isTrue);
    expect(series.sliceCount, 1);
    // The original file is kept, exactly as a plain .dcm import does.
    expect(series.singleOriginalPath, isNotNull);
    expect(File(series.singleOriginalPath!).existsSync(), isTrue);
  });

  test('a zip with nothing readable says so', () async {
    final zip = makeZip('empty.zip', [
      ArchiveFile.string('notes.txt', 'no images here'),
    ]);

    expect(
      () => importDicomZip(zipPath: zip, baseName: 'zip_empty'),
      throwsA(
        isA<DicomParseException>().having(
          (e) => e.message,
          'message',
          contains('No DICOM files were found'),
        ),
      ),
    );
  });

  test('a file that is not a zip at all says so', () async {
    final notZip = p.join(workDir.path, 'notazip.zip');
    File(notZip).writeAsBytesSync(slice);

    expect(
      () => importDicomZip(zipPath: notZip, baseName: 'zip_broken'),
      throwsA(isA<DicomParseException>()),
    );
  });

  test('a broken slice inside a good archive is skipped, not fatal', () async {
    final zip = makeZip('mixed.zip', [
      ArchiveFile.bytes('IMG0001.dcm', slice),
      // Has the DICM marker but nothing valid after it.
      ArchiveFile.bytes(
        'IMG0002.dcm',
        Uint8List.fromList([
          ...List.filled(128, 0),
          0x44, 0x49, 0x43, 0x4D,
          ...List.filled(64, 9),
        ]),
      ),
    ]);

    final series = await importDicomZip(zipPath: zip, baseName: 'zip_mixed');

    expect(series.sliceCount, 1);
    expect(series.skipped, 1);
  });

  test('caps oversized archives and reports how many were left out', () async {
    final zip = makeZip('big.zip', [
      for (var i = 0; i < 7; i++)
        ArchiveFile.bytes('IMG${i.toString().padLeft(4, '0')}.dcm', slice),
    ]);

    final series = await importDicomZip(
      zipPath: zip,
      baseName: 'zip_cap',
      cap: 4,
    );

    expect(series.sliceCount, 4);
    expect(series.skipped, 3);
  });

  test('reports progress while unpacking', () async {
    final zip = makeZip('progress.zip', [
      for (var i = 0; i < 3; i++) ArchiveFile.bytes('IMG$i.dcm', slice),
    ]);

    final seen = <String>[];
    await importDicomZip(
      zipPath: zip,
      baseName: 'zip_progress',
      onProgress: (done, total) => seen.add('$done/$total'),
    );

    expect(seen, ['1/3', '2/3', '3/3']);
  });

  test('recognises DICOM by its marker, not its name', () {
    expect(looksLikeDicom(slice), isTrue);
    expect(looksLikeDicom(Uint8List.fromList(List.filled(200, 0))), isFalse);
    expect(looksLikeDicom(Uint8List.fromList([1, 2, 3])), isFalse);
  });
}
