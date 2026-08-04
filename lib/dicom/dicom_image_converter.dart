import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dicom_parser.dart';

/// Bytes ready to write to disk and display with Image.file/Image.memory.
class DicomRenderResult {
  const DicomRenderResult({required this.bytes, required this.extension});
  final Uint8List bytes;

  /// 'jpg' when the source pixel data was already JPEG (no re-encoding
  /// needed), 'png' when it was decoded from raw/native pixel samples.
  final String extension;
}

/// Turns a parsed [DicomDataset] into plain image bytes Flutter can already
/// render, so the rest of the app never needs to know a tooth image came
/// from a DICOM file.
class DicomImageConverter {
  const DicomImageConverter();

  Future<DicomRenderResult> convert(DicomDataset dataset) async {
    if (dataset.compression == DicomCompression.jpegBaseline) {
      // Already a JPEG byte stream - Flutter can decode this as-is.
      return DicomRenderResult(bytes: dataset.pixelBytes, extension: 'jpg');
    }

    final rgba = _toRgba(dataset);
    final image = await _decodeRgba(rgba, dataset.info.columns, dataset.info.rows);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw const DicomParseException('Could not render this DICOM image.');
    }
    return DicomRenderResult(bytes: byteData.buffer.asUint8List(), extension: 'png');
  }

  Future<ui.Image> _decodeRgba(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  Uint8List _toRgba(DicomDataset dataset) {
    final info = dataset.info;
    final width = info.columns;
    final height = info.rows;
    final samplesPerPixel = info.samplesPerPixel;
    final bytesPerSample = info.bitsAllocated <= 8 ? 1 : 2;
    final pixelCount = width * height;
    final data = ByteData.sublistView(dataset.pixelBytes);
    final endian = dataset.bigEndian ? Endian.big : Endian.little;
    final isPlanar = info.planarConfiguration == 1 && samplesPerPixel > 1;

    int readSample(int sampleIndex) {
      final byteOffset = sampleIndex * bytesPerSample;
      if (bytesPerSample == 1) {
        final v = data.getUint8(byteOffset);
        return info.pixelRepresentationSigned ? v.toSigned(8) : v;
      }
      return info.pixelRepresentationSigned
          ? data.getInt16(byteOffset, endian)
          : data.getUint16(byteOffset, endian);
    }

    final rescaled = Float64List(pixelCount * samplesPerPixel);
    var minVal = double.infinity;
    var maxVal = double.negativeInfinity;

    for (var i = 0; i < pixelCount; i++) {
      for (var c = 0; c < samplesPerPixel; c++) {
        final sampleIndex = isPlanar ? (c * pixelCount + i) : (i * samplesPerPixel + c);
        final value = readSample(sampleIndex) * info.rescaleSlope + info.rescaleIntercept;
        rescaled[i * samplesPerPixel + c] = value;
        if (samplesPerPixel == 1) {
          if (value < minVal) minVal = value;
          if (value > maxVal) maxVal = value;
        }
      }
    }

    final rgba = Uint8List(pixelCount * 4);

    if (samplesPerPixel >= 3) {
      for (var i = 0; i < pixelCount; i++) {
        rgba[i * 4 + 0] = _clampByte(rescaled[i * samplesPerPixel + 0]);
        rgba[i * 4 + 1] = _clampByte(rescaled[i * samplesPerPixel + 1]);
        rgba[i * 4 + 2] = _clampByte(rescaled[i * samplesPerPixel + 2]);
        rgba[i * 4 + 3] = 255;
      }
      return rgba;
    }

    final double center;
    final double width_;
    if (info.windowCenter != null && info.windowWidth != null && info.windowWidth! > 0) {
      center = info.windowCenter!;
      width_ = info.windowWidth!;
    } else {
      final double range = (maxVal.isFinite && minVal.isFinite) ? (maxVal - minVal) : 255.0;
      final double safeRange = range <= 0 ? 1.0 : range;
      center = minVal.isFinite ? minVal + safeRange / 2 : 128.0;
      width_ = safeRange;
    }
    final invert = info.photometricInterpretation.toUpperCase() == 'MONOCHROME1';
    final lowEdge = center - 0.5 - (width_ - 1) / 2;
    final highEdge = center - 0.5 + (width_ - 1) / 2;

    for (var i = 0; i < pixelCount; i++) {
      final v = rescaled[i];
      int gray;
      if (v <= lowEdge) {
        gray = 0;
      } else if (v > highEdge) {
        gray = 255;
      } else {
        gray = (((v - (center - 0.5)) / (width_ - 1) + 0.5) * 255).round();
      }
      if (invert) gray = 255 - gray;
      final byte = _clampByte(gray.toDouble());
      rgba[i * 4 + 0] = byte;
      rgba[i * 4 + 1] = byte;
      rgba[i * 4 + 2] = byte;
      rgba[i * 4 + 3] = 255;
    }
    return rgba;
  }
}

int _clampByte(double v) {
  final i = v.round();
  if (i < 0) return 0;
  if (i > 255) return 255;
  return i;
}
