import 'dart:io';

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
  late Uint8List slice;

  setUp(() {
    docsDir = Directory.systemTemp.createTempSync('stom_series_');
    _mockDocumentsDirectory(docsDir);
    slice = File('test/fixtures/sample_uncompressed.dcm').readAsBytesSync();
  });

  tearDown(() {
    if (docsDir.existsSync()) docsDir.deleteSync(recursive: true);
  });

  test('renders every slice of a series into one folder', () async {
    final series = await importDicomSeries(
      files: [
        (name: 'img_003.dcm', bytes: slice),
        (name: 'img_001.dcm', bytes: slice),
        (name: 'img_002.dcm', bytes: slice),
      ],
      baseName: 'series_test',
    );

    expect(series.sliceCount, 3);
    expect(series.skipped, 0);
    for (var i = 0; i < 3; i++) {
      final file = File(slicePath(series.seriesDir, i));
      expect(file.existsSync(), isTrue, reason: 'slice $i');
      expect(file.lengthSync(), greaterThan(0));
    }
    // Opens in the middle of the stack, where the anatomy usually is.
    expect(p.basename(series.firstSlicePath), sliceFileName(1));
  });

  test('a file that is not DICOM is skipped, not fatal', () async {
    final series = await importDicomSeries(
      files: [
        (name: 'good.dcm', bytes: slice),
        (name: 'broken.dcm', bytes: Uint8List.fromList(List.filled(300, 7))),
      ],
      baseName: 'series_skip',
    );

    expect(series.sliceCount, 1);
    expect(series.skipped, 1);
  });

  test('a selection with nothing readable fails with a clear message', () async {
    expect(
      () => importDicomSeries(
        files: [(name: 'broken.dcm', bytes: Uint8List.fromList(List.filled(300, 7)))],
        baseName: 'series_bad',
      ),
      throwsA(isA<DicomParseException>()),
    );
  });

  test('huge exports are capped instead of filling the phone', () async {
    final series = await importDicomSeries(
      files: [
        for (var i = 0; i < 6; i++) (name: 'img_$i.dcm', bytes: slice),
      ],
      baseName: 'series_cap',
      cap: 4,
    );

    expect(series.sliceCount, 4);
    expect(series.skipped, 2);
  });

  test('reports progress slice by slice', () async {
    final seen = <String>[];
    await importDicomSeries(
      files: [
        for (var i = 0; i < 3; i++) (name: 'img_$i.dcm', bytes: slice),
      ],
      baseName: 'series_progress',
      onProgress: (done, total) => seen.add('$done/$total'),
    );

    expect(seen, ['1/3', '2/3', '3/3']);
  });

  test('a single DICOM keeps its original file alongside the rendered one', () async {
    final imported = await importDicomBytes(bytes: slice, baseName: 'single_test');

    expect(File(imported.displayPath).existsSync(), isTrue);
    expect(File(imported.originalPath).existsSync(), isTrue);
    expect(p.extension(imported.originalPath), '.dcm');
    expect(File(imported.originalPath).readAsBytesSync().length, slice.length);
  });
}
