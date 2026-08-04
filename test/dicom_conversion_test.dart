import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:stom/dicom/dicom_image_converter.dart';
import 'package:stom/dicom/dicom_parser.dart';

Future<ui.Image> _decode(List<int> bytes) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(Uint8List.fromList(bytes), completer.complete);
  return completer.future;
}

void main() {
  test('uncompressed (native) DICOM converts to a valid, correctly sized PNG', () async {
    final bytes = File('test/fixtures/sample_uncompressed.dcm').readAsBytesSync();
    final dataset = const DicomParser().parse(bytes);
    final result = await const DicomImageConverter().convert(dataset);

    expect(result.extension, 'png');
    final image = await _decode(result.bytes);
    expect(image.width, 64);
    expect(image.height, 64);
  });

  test('JPEG-compressed DICOM pixel data decodes as a valid, correctly sized image', () async {
    final bytes = File('test/fixtures/sample_jpeg.dcm').readAsBytesSync();
    final dataset = const DicomParser().parse(bytes);
    final result = await const DicomImageConverter().convert(dataset);

    expect(result.extension, 'jpg');
    final image = await _decode(result.bytes);
    expect(image.width, 48);
    expect(image.height, 48);
  });

  test('non-DICOM bytes are rejected with a clear error', () {
    final bytes = Uint8List.fromList(List<int>.filled(200, 0));
    expect(
      () => const DicomParser().parse(bytes),
      throwsA(isA<DicomParseException>()),
    );
  });
}
