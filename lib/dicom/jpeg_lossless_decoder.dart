import 'dart:typed_data';

import 'dicom_parser.dart' show DicomParseException;

/// Decoded output of a JPEG Lossless (ITU-T T.81 Process 14, Huffman)
/// codestream: raw, unsigned sample values in row-major order, interleaved
/// by component (matches how DICOM lays out native pixel data).
class JpegLosslessResult {
  const JpegLosslessResult({
    required this.width,
    required this.height,
    required this.precision,
    required this.componentCount,
    required this.samples,
  });

  final int width;
  final int height;
  final int precision;
  final int componentCount;
  final Uint16List samples;
}

/// Decodes the JPEG Lossless variant DICOM actually uses (transfer syntaxes
/// 1.2.840.10008.1.2.4.57 and .4.70): predictive/differential coding with
/// Huffman-coded differences, no DCT, no chroma subsampling. This is a
/// different codec from baseline/JPEG-DCT and gets its own decoder.
class JpegLosslessDecoder {
  const JpegLosslessDecoder();

  JpegLosslessResult decode(Uint8List bytes) {
    if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const DicomParseException('Not a valid JPEG Lossless stream (missing SOI marker).');
    }

    var pos = 2;
    int? width;
    int? height;
    int? precision;
    int? numComponents;
    final componentIds = <int>[];
    final huffmanTables = <int, _HuffmanTable>{};
    var restartInterval = 0;

    while (pos < bytes.length - 1) {
      if (bytes[pos] != 0xFF) {
        pos++;
        continue;
      }
      while (pos < bytes.length && bytes[pos] == 0xFF) {
        pos++;
      }
      if (pos >= bytes.length) break;
      final marker = bytes[pos];
      pos++;

      if (marker == 0xD9) break; // EOI
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        continue; // TEM / stray restart marker, no payload
      }
      if (pos + 1 >= bytes.length) break;

      final segLength = (bytes[pos] << 8) | bytes[pos + 1];
      final segStart = pos + 2;
      final segEnd = pos + segLength;

      if (marker == 0xC3) {
        var p = segStart;
        precision = bytes[p];
        p += 1;
        height = (bytes[p] << 8) | bytes[p + 1];
        p += 2;
        width = (bytes[p] << 8) | bytes[p + 1];
        p += 2;
        numComponents = bytes[p];
        p += 1;
        for (var i = 0; i < numComponents; i++) {
          final id = bytes[p];
          final sampling = bytes[p + 1];
          if ((sampling >> 4) != 1 || (sampling & 0x0F) != 1) {
            throw const DicomParseException(
              'This DICOM file uses chroma-subsampled JPEG Lossless data, which isn\'t supported.',
            );
          }
          componentIds.add(id);
          p += 3;
        }
      } else if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        throw const DicomParseException(
          'This DICOM file\'s embedded JPEG is not lossless-encoded (unsupported here).',
        );
      } else if (marker == 0xC4) {
        var p = segStart;
        while (p < segEnd) {
          final tableId = bytes[p] & 0x0F;
          p += 1;
          final counts = List<int>.generate(16, (i) => bytes[p + i]);
          p += 16;
          final table = _HuffmanTable();
          var code = 0;
          for (var length = 1; length <= 16; length++) {
            for (var i = 0; i < counts[length - 1]; i++) {
              table.add(length, code, bytes[p]);
              p += 1;
              code += 1;
            }
            code <<= 1;
          }
          huffmanTables[tableId] = table;
        }
      } else if (marker == 0xDD) {
        restartInterval = (bytes[segStart] << 8) | bytes[segStart + 1];
      } else if (marker == 0xDA) {
        if (width == null || height == null || precision == null || numComponents == null) {
          throw const DicomParseException('Malformed JPEG Lossless stream (missing frame header).');
        }
        var p = segStart;
        final ns = bytes[p];
        p += 1;
        final scanTableForComponent = <int, int>{};
        for (var i = 0; i < ns; i++) {
          final cs = bytes[p];
          final tdTa = bytes[p + 1];
          scanTableForComponent[cs] = tdTa >> 4;
          p += 2;
        }
        final predictorSelection = bytes[p];
        p += 2; // predictor selection value, then skip Se (unused)
        final pointTransform = bytes[p] & 0x0F;

        final reader = _BitReader(bytes, p + 1);
        final samples = _decodeScan(
          reader: reader,
          width: width,
          height: height,
          precision: precision,
          numComponents: ns,
          componentIds: componentIds,
          scanTableForComponent: scanTableForComponent,
          huffmanTables: huffmanTables,
          predictorSelection: predictorSelection,
          pointTransform: pointTransform,
          restartInterval: restartInterval,
        );

        return JpegLosslessResult(
          width: width,
          height: height,
          precision: precision,
          componentCount: ns,
          samples: samples,
        );
      }

      pos = segEnd;
    }

    throw const DicomParseException('This DICOM file\'s JPEG Lossless stream is missing scan data.');
  }

  Uint16List _decodeScan({
    required _BitReader reader,
    required int width,
    required int height,
    required int precision,
    required int numComponents,
    required List<int> componentIds,
    required Map<int, int> scanTableForComponent,
    required Map<int, _HuffmanTable> huffmanTables,
    required int predictorSelection,
    required int pointTransform,
    required int restartInterval,
  }) {
    final samples = Uint16List(width * height * numComponents);
    final defaultValue = 1 << (precision - pointTransform - 1);
    final precisionMask = (1 << precision) - 1;
    final prevRow = List<Uint16List>.generate(numComponents, (_) => Uint16List(width));
    final curRow = List<Uint16List>.generate(numComponents, (_) => Uint16List(width));

    var mcuCount = 0;
    var justRestarted = false;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        for (var c = 0; c < numComponents; c++) {
          final tableId = scanTableForComponent[componentIds[c]] ?? 0;
          final table = huffmanTables[tableId];
          if (table == null) {
            throw const DicomParseException('This DICOM file references an undefined Huffman table.');
          }

          final category = _decodeHuffmanSymbol(reader, table);
          int diff;
          if (category == 0) {
            diff = 0;
          } else if (category == 16) {
            diff = 32768;
          } else {
            final v = reader.readBits(category);
            diff = v < (1 << (category - 1)) ? v - (1 << category) + 1 : v;
          }

          final atRowStart = justRestarted || x == 0;
          int predictor;
          if (y == 0 && atRowStart) {
            predictor = defaultValue;
          } else if (y == 0) {
            predictor = curRow[c][x - 1];
          } else if (atRowStart) {
            predictor = prevRow[c][x];
          } else {
            predictor = _predict(predictorSelection, curRow[c][x - 1], prevRow[c][x], prevRow[c][x - 1]);
          }

          final value = (predictor + diff) & precisionMask;
          curRow[c][x] = value;
          samples[(y * width + x) * numComponents + c] = value;
        }
        justRestarted = false;

        mcuCount++;
        final isLastMcu = x == width - 1 && y == height - 1;
        if (restartInterval > 0 && mcuCount % restartInterval == 0 && !isLastMcu) {
          reader.consumeRestartMarker();
          justRestarted = true;
        }
      }
      for (var c = 0; c < numComponents; c++) {
        prevRow[c].setAll(0, curRow[c]);
      }
    }

    return samples;
  }

  int _predict(int selection, int ra, int rb, int rc) {
    switch (selection) {
      case 1:
        return ra;
      case 2:
        return rb;
      case 3:
        return rc;
      case 4:
        return ra + rb - rc;
      case 5:
        return ra + ((rb - rc) >> 1);
      case 6:
        return rb + ((ra - rc) >> 1);
      case 7:
        return (ra + rb) >> 1;
      default:
        return ra;
    }
  }

  int _decodeHuffmanSymbol(_BitReader reader, _HuffmanTable table) {
    var code = 0;
    for (var length = 1; length <= 16; length++) {
      code = (code << 1) | reader.readBit();
      final symbol = table.lookup(length, code);
      if (symbol != null) return symbol;
    }
    throw const DicomParseException('Invalid Huffman code in JPEG Lossless data.');
  }
}

class _HuffmanTable {
  final Map<int, int> _codes = {};
  void add(int length, int code, int symbol) => _codes[(length << 20) | code] = symbol;
  int? lookup(int length, int code) => _codes[(length << 20) | code];
}

class _BitReader {
  _BitReader(this.bytes, int startPos) : _pos = startPos;

  final Uint8List bytes;
  int _pos;
  int _bitBuffer = 0;
  int _bitCount = 0;

  int readBit() {
    if (_bitCount == 0) {
      if (_pos >= bytes.length) {
        throw const DicomParseException('Unexpected end of JPEG Lossless data.');
      }
      final b = bytes[_pos++];
      if (b == 0xFF && _pos < bytes.length && bytes[_pos] == 0x00) {
        _pos++; // discard stuffed zero
      }
      _bitBuffer = b;
      _bitCount = 8;
    }
    _bitCount--;
    return (_bitBuffer >> _bitCount) & 1;
  }

  int readBits(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 1) | readBit();
    }
    return v;
  }

  void consumeRestartMarker() {
    _bitBuffer = 0;
    _bitCount = 0;
    if (_pos + 1 < bytes.length && bytes[_pos] == 0xFF && bytes[_pos + 1] >= 0xD0 && bytes[_pos + 1] <= 0xD7) {
      _pos += 2;
    }
  }
}
