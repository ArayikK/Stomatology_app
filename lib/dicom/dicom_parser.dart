import 'dart:typed_data';

/// Thrown when a DICOM file can't be parsed, or uses a compression format
/// this parser doesn't decode. The message is written to be shown directly
/// to the dentist in the UI.
class DicomParseException implements Exception {
  const DicomParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The handful of pixel-data compression schemes this parser understands.
/// Everything else (JPEG Lossless, JPEG 2000, RLE, deflated syntaxes, ...)
/// is reported as unsupported rather than guessed at.
enum DicomCompression { native, jpegBaseline }

class DicomPixelInfo {
  const DicomPixelInfo({
    required this.rows,
    required this.columns,
    required this.bitsAllocated,
    required this.samplesPerPixel,
    required this.photometricInterpretation,
    required this.pixelRepresentationSigned,
    required this.planarConfiguration,
    this.windowCenter,
    this.windowWidth,
    this.rescaleIntercept = 0,
    this.rescaleSlope = 1,
  });

  final int rows;
  final int columns;
  final int bitsAllocated;
  final int samplesPerPixel;
  final String photometricInterpretation;
  final bool pixelRepresentationSigned;
  final int planarConfiguration;
  final double? windowCenter;
  final double? windowWidth;
  final double rescaleIntercept;
  final double rescaleSlope;
}

class DicomDataset {
  const DicomDataset({
    required this.info,
    required this.pixelBytes,
    required this.compression,
    required this.bigEndian,
  });

  final DicomPixelInfo info;
  final Uint8List pixelBytes;
  final DicomCompression compression;
  final bool bigEndian;
}

const int _kPixelDataTag = (0x7FE0 << 16) | 0x0010;
const int _kItemTag = (0xFFFE << 16) | 0xE000;
const int _kItemDelimTag = (0xFFFE << 16) | 0xE00D;
const int _kSeqDelimTag = (0xFFFE << 16) | 0xE0DD;

const int _kTagSamplesPerPixel = (0x0028 << 16) | 0x0002;
const int _kTagPhotometricInterpretation = (0x0028 << 16) | 0x0004;
const int _kTagPlanarConfiguration = (0x0028 << 16) | 0x0006;
const int _kTagRows = (0x0028 << 16) | 0x0010;
const int _kTagColumns = (0x0028 << 16) | 0x0011;
const int _kTagBitsAllocated = (0x0028 << 16) | 0x0100;
const int _kTagPixelRepresentation = (0x0028 << 16) | 0x0103;
const int _kTagWindowCenter = (0x0028 << 16) | 0x1050;
const int _kTagWindowWidth = (0x0028 << 16) | 0x1051;
const int _kTagRescaleIntercept = (0x0028 << 16) | 0x1052;
const int _kTagRescaleSlope = (0x0028 << 16) | 0x1053;
const int _kTagFileMetaGroupLength = (0x0002 << 16) | 0x0000;
const int _kTagTransferSyntaxUid = (0x0002 << 16) | 0x0010;

// Explicit-VR value representations that use a 4-byte length (with 2
// reserved bytes first) instead of a plain 2-byte length.
const Set<String> _kExplicitLongVRs = {
  'OB', 'OW', 'OF', 'OD', 'OL', 'SQ', 'UC', 'UR', 'UT', 'UN',
};

/// A small, dependency-free DICOM (Part 10) reader. Covers what real
/// single-frame dental periapical/panoramic exports actually use: Implicit
/// VR Little Endian, Explicit VR Little/Big Endian, and JPEG Baseline
/// compressed pixel data. Anything else throws [DicomParseException] with a
/// message explaining what wasn't supported, instead of misreading it.
class DicomParser {
  const DicomParser();

  DicomDataset parse(Uint8List bytes) {
    if (bytes.length < 132 || _asciiAt(bytes, 128, 4) != 'DICM') {
      throw const DicomParseException(
        'This file doesn\'t look like a DICOM file (missing the "DICM" marker).',
      );
    }

    final meta = _ByteCursor(bytes, bigEndian: false)..offset = 132;
    String? transferSyntaxUid;
    int? metaGroupLength;

    while (!meta.atEnd) {
      final group = meta.readUint16();
      if (group != 0x0002) {
        meta.offset -= 2;
        break;
      }
      final element = meta.readUint16();
      final vr = meta.readAsciiString(2);
      int length;
      if (_kExplicitLongVRs.contains(vr)) {
        meta.readUint16();
        length = meta.readUint32();
      } else {
        length = meta.readUint16();
      }
      final valueBytes = meta.readBytes(length);
      final tag = (group << 16) | element;
      if (tag == _kTagFileMetaGroupLength && length >= 4) {
        metaGroupLength = ByteData.sublistView(valueBytes).getUint32(0, Endian.little);
      } else if (tag == _kTagTransferSyntaxUid) {
        transferSyntaxUid = _cleanString(String.fromCharCodes(valueBytes));
      }
      final groupLength = metaGroupLength;
      if (groupLength != null && meta.offset >= 144 + groupLength) break;
    }

    if (transferSyntaxUid == null) {
      throw const DicomParseException(
        'Missing transfer syntax in this DICOM file\'s header.',
      );
    }

    final compression = _compressionForTransferSyntax(transferSyntaxUid);
    if (compression == null) {
      throw DicomParseException(
        'This DICOM file uses a compression format ("$transferSyntaxUid") '
        'that isn\'t supported yet. Uncompressed and JPEG-compressed DICOM '
        'images are supported.',
      );
    }
    final bigEndian = transferSyntaxUid == '1.2.840.10008.1.2.2';
    final explicitVr = transferSyntaxUid != '1.2.840.10008.1.2';

    final cursor = _ByteCursor(bytes, bigEndian: bigEndian)..offset = meta.offset;

    int? rows;
    int? columns;
    int? bitsAllocated;
    int? samplesPerPixel;
    int? pixelRepresentation;
    int? planarConfiguration;
    String photometricInterpretation = 'MONOCHROME2';
    double? windowCenter;
    double? windowWidth;
    double rescaleIntercept = 0;
    double rescaleSlope = 1;
    Uint8List? pixelBytes;

    while (!cursor.atEnd) {
      final elementStart = cursor.offset;
      final group = cursor.readUint16();
      final element = cursor.readUint16();
      final tag = (group << 16) | element;

      if (tag == _kSeqDelimTag) {
        if (cursor.remaining >= 4) cursor.readUint32();
        continue;
      }

      String vr = 'UN';
      int length;
      if (explicitVr) {
        vr = cursor.readAsciiString(2);
        if (_kExplicitLongVRs.contains(vr)) {
          cursor.readUint16();
          length = cursor.readUint32();
        } else {
          length = cursor.readUint16();
        }
      } else {
        length = cursor.readUint32();
      }

      final undefinedLength = length == 0xFFFFFFFF;

      if (tag == _kPixelDataTag) {
        pixelBytes = undefinedLength
            ? _readEncapsulatedPixelData(cursor)
            : cursor.readBytes(length);
        continue;
      }

      if (undefinedLength) {
        _skipSequenceItems(cursor, explicitVr);
        continue;
      }

      switch (tag) {
        case _kTagSamplesPerPixel:
          samplesPerPixel = _readUsLike(cursor, length);
        case _kTagPhotometricInterpretation:
          photometricInterpretation = cursor.readAsciiString(length).trim();
        case _kTagPlanarConfiguration:
          planarConfiguration = _readUsLike(cursor, length);
        case _kTagRows:
          rows = _readUsLike(cursor, length);
        case _kTagColumns:
          columns = _readUsLike(cursor, length);
        case _kTagBitsAllocated:
          bitsAllocated = _readUsLike(cursor, length);
        case _kTagPixelRepresentation:
          pixelRepresentation = _readUsLike(cursor, length);
        case _kTagWindowCenter:
          windowCenter = _readFirstNumericString(cursor, length);
        case _kTagWindowWidth:
          windowWidth = _readFirstNumericString(cursor, length);
        case _kTagRescaleIntercept:
          rescaleIntercept = _readFirstNumericString(cursor, length) ?? 0;
        case _kTagRescaleSlope:
          rescaleSlope = _readFirstNumericString(cursor, length) ?? 1;
        default:
          cursor.readBytes(length);
      }

      if (cursor.offset <= elementStart) {
        throw const DicomParseException('This DICOM file appears to be malformed.');
      }
    }

    if (rows == null || columns == null || pixelBytes == null) {
      throw const DicomParseException(
        'This DICOM file is missing image dimensions or pixel data.',
      );
    }

    return DicomDataset(
      info: DicomPixelInfo(
        rows: rows,
        columns: columns,
        bitsAllocated: bitsAllocated ?? 8,
        samplesPerPixel: samplesPerPixel ?? 1,
        photometricInterpretation: photometricInterpretation,
        pixelRepresentationSigned: pixelRepresentation == 1,
        planarConfiguration: planarConfiguration ?? 0,
        windowCenter: windowCenter,
        windowWidth: windowWidth,
        rescaleIntercept: rescaleIntercept,
        rescaleSlope: rescaleSlope,
      ),
      pixelBytes: pixelBytes,
      compression: compression,
      bigEndian: bigEndian,
    );
  }

  Uint8List _readEncapsulatedPixelData(_ByteCursor cursor) {
    _expectTag(cursor, _kItemTag);
    final offsetTableLength = cursor.readUint32();
    cursor.readBytes(offsetTableLength);

    final fragments = <Uint8List>[];
    while (true) {
      final group = cursor.readUint16();
      final element = cursor.readUint16();
      final tag = (group << 16) | element;
      if (tag == _kSeqDelimTag) {
        cursor.readUint32();
        break;
      }
      if (tag != _kItemTag) {
        throw const DicomParseException(
          'This DICOM file\'s compressed pixel data is malformed.',
        );
      }
      final itemLength = cursor.readUint32();
      fragments.add(cursor.readBytes(itemLength));
    }

    if (fragments.length == 1) return fragments.first;
    final total = fragments.fold<int>(0, (sum, f) => sum + f.length);
    final combined = Uint8List(total);
    var offset = 0;
    for (final f in fragments) {
      combined.setRange(offset, offset + f.length, f);
      offset += f.length;
    }
    return combined;
  }

  void _skipSequenceItems(_ByteCursor cursor, bool explicitVr) {
    while (true) {
      final group = cursor.readUint16();
      final element = cursor.readUint16();
      final tag = (group << 16) | element;
      if (tag == _kSeqDelimTag) {
        cursor.readUint32();
        return;
      }
      if (tag != _kItemTag) {
        throw const DicomParseException('This DICOM file has a malformed sequence.');
      }
      final itemLength = cursor.readUint32();
      if (itemLength == 0xFFFFFFFF) {
        _skipItemContents(cursor, explicitVr);
      } else {
        cursor.readBytes(itemLength);
      }
    }
  }

  void _skipItemContents(_ByteCursor cursor, bool explicitVr) {
    while (true) {
      final saved = cursor.offset;
      final group = cursor.readUint16();
      final element = cursor.readUint16();
      final tag = (group << 16) | element;
      if (tag == _kItemDelimTag) {
        cursor.readUint32();
        return;
      }
      cursor.offset = saved;
      _skipOneDatasetElement(cursor, explicitVr);
    }
  }

  void _skipOneDatasetElement(_ByteCursor cursor, bool explicitVr) {
    cursor.readUint16();
    cursor.readUint16();
    String vr = 'UN';
    int length;
    if (explicitVr) {
      vr = cursor.readAsciiString(2);
      if (_kExplicitLongVRs.contains(vr)) {
        cursor.readUint16();
        length = cursor.readUint32();
      } else {
        length = cursor.readUint16();
      }
    } else {
      length = cursor.readUint32();
    }
    if (length == 0xFFFFFFFF) {
      _skipSequenceItems(cursor, explicitVr);
    } else {
      cursor.readBytes(length);
    }
  }

  void _expectTag(_ByteCursor cursor, int expected) {
    final group = cursor.readUint16();
    final element = cursor.readUint16();
    final tag = (group << 16) | element;
    if (tag != expected) {
      throw const DicomParseException('This DICOM file\'s pixel data is malformed.');
    }
  }

  int _readUsLike(_ByteCursor cursor, int length) {
    if (length == 2) return cursor.readUint16();
    if (length == 4) return cursor.readUint32();
    final s = cursor.readAsciiString(length);
    return int.tryParse(s.split('\\').first.trim()) ?? 0;
  }

  double? _readFirstNumericString(_ByteCursor cursor, int length) {
    final s = cursor.readAsciiString(length);
    final first = s.split('\\').first.trim();
    return double.tryParse(first);
  }
}

DicomCompression? _compressionForTransferSyntax(String uid) {
  switch (uid) {
    case '1.2.840.10008.1.2':
    case '1.2.840.10008.1.2.1':
    case '1.2.840.10008.1.2.2':
      return DicomCompression.native;
    case '1.2.840.10008.1.2.4.50':
    case '1.2.840.10008.1.2.4.51':
      return DicomCompression.jpegBaseline;
    default:
      return null;
  }
}

String _asciiAt(Uint8List bytes, int offset, int length) {
  return String.fromCharCodes(bytes, offset, offset + length);
}

String _cleanString(String s) {
  return s.replaceAll('\x00', '').trim();
}

class _ByteCursor {
  _ByteCursor(this.bytes, {required this.bigEndian}) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  final bool bigEndian;
  int offset = 0;

  int get remaining => bytes.length - offset;
  bool get atEnd => offset >= bytes.length;

  int readUint16() {
    final v = data.getUint16(offset, bigEndian ? Endian.big : Endian.little);
    offset += 2;
    return v;
  }

  int readUint32() {
    final v = data.getUint32(offset, bigEndian ? Endian.big : Endian.little);
    offset += 4;
    return v;
  }

  Uint8List readBytes(int length) {
    final slice = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return slice;
  }

  String readAsciiString(int length) {
    final b = readBytes(length);
    var end = b.length;
    while (end > 0 && (b[end - 1] == 0 || b[end - 1] == 32)) {
      end--;
    }
    return String.fromCharCodes(b, 0, end);
  }
}
