import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stom/dicom/dicom_parser.dart';
import 'package:stom/models/annotation_shape.dart';
import 'package:stom/models/image_view_settings.dart';

/// A 1000x1000 image at 0.15 mm/pixel - the scale of the bundled CBCT slice.
const _scale = ImageScale(imageSize: Size(1000, 1000), mmPerPixel: 0.15);
const _uncalibrated = ImageScale(imageSize: Size(1000, 1000));

void main() {
  group('measurement', () {
    test('reports millimetres when the image is calibrated', () {
      // 0.2 of 1000 px = 200 px = 30 mm at 0.15 mm/px.
      final mm = _scale.millimetres(const Offset(0.1, 0.5), const Offset(0.3, 0.5));
      expect(mm, closeTo(30, 0.001));
      expect(
        _scale.describeDistance(const Offset(0.1, 0.5), const Offset(0.3, 0.5)),
        '30.0 mm',
      );
    });

    test('falls back to pixels when there is no scale', () {
      expect(_uncalibrated.millimetres(const Offset(0, 0), const Offset(0.1, 0)), isNull);
      expect(
        _uncalibrated.describeDistance(const Offset(0, 0), const Offset(0.1, 0)),
        '100 px',
      );
    });

    test('measures diagonals, not just straight lines', () {
      // 300 px across, 400 px down -> 500 px -> 75 mm.
      final mm = _scale.millimetres(const Offset(0, 0), const Offset(0.3, 0.4));
      expect(mm, closeTo(75, 0.001));
    });

    test('a non-square image still measures correctly', () {
      const wide = ImageScale(imageSize: Size(2000, 500), mmPerPixel: 0.1);
      // 0.5 of 2000 = 1000 px -> 100 mm.
      expect(wide.millimetres(const Offset(0, 0), const Offset(0.5, 0)), closeTo(100, 0.001));
      // 0.5 of 500 = 250 px -> 25 mm.
      expect(wide.millimetres(const Offset(0, 0), const Offset(0, 0.5)), closeTo(25, 0.001));
    });
  });

  group('implant template', () {
    test('a 10 mm implant is drawn exactly 10 mm long', () {
      const platform = Offset(0.5, 0.2);
      const drag = Offset(0.6, 0.9); // direction only
      final length = _scale.normalizedLengthForMm(10, drag - platform);
      final direction = (drag - platform) / (drag - platform).distance;
      final apex = platform + direction * length;
      expect(_scale.millimetres(platform, apex), closeTo(10, 0.01));
    });

    test('holds on a non-square image whatever way it points', () {
      const wide = ImageScale(imageSize: Size(1600, 900), mmPerPixel: 0.2);
      for (final drag in [const Offset(1, 0), const Offset(0, 1), const Offset(0.7, 0.3)]) {
        const platform = Offset(0.2, 0.2);
        final length = wide.normalizedLengthForMm(13, drag);
        final apex = platform + drag / drag.distance * length;
        expect(wide.millimetres(platform, apex), closeTo(13, 0.01), reason: '$drag');
      }
    });
  });

  group('angle', () {
    test('a right angle reads 90 degrees', () {
      final degrees = angleDegrees(
        const Offset(0.5, 0.2),
        const Offset(0.5, 0.5),
        const Offset(0.8, 0.5),
        const Size(1000, 1000),
      );
      expect(degrees, closeTo(90, 0.001));
    });

    test('a straight line reads 180 degrees', () {
      final degrees = angleDegrees(
        const Offset(0.2, 0.5),
        const Offset(0.5, 0.5),
        const Offset(0.9, 0.5),
        const Size(1000, 1000),
      );
      expect(degrees, closeTo(180, 0.001));
    });
  });

  group('distance to the canal', () {
    test('measures the shortest distance to the traced line', () {
      final canal = [const Offset(0.1, 0.8), const Offset(0.9, 0.8)];
      // 0.1 above the canal = 100 px = 15 mm.
      final mm = distanceToPolyline(const Offset(0.5, 0.7), canal, _scale);
      expect(mm, closeTo(15, 0.001));
    });

    test('clamps to the ends of the segment', () {
      final canal = [const Offset(0.4, 0.8), const Offset(0.6, 0.8)];
      // Beyond the right end: nearest point is that end itself.
      final mm = distanceToPolyline(const Offset(0.9, 0.8), canal, _scale);
      expect(mm, closeTo(0.3 * 1000 * 0.15, 0.001));
    });

    test('needs at least two points', () {
      expect(distanceToPolyline(const Offset(0.5, 0.5), [const Offset(0, 0)], _scale), isNull);
    });
  });

  group('view settings', () {
    test('untouched settings leave the image alone', () {
      final m = const ImageViewSettings().colorMatrix();
      expect(m[0], closeTo(1, 0.0001)); // red scale
      expect(m[4], closeTo(0, 0.0001)); // red offset
      expect(const ImageViewSettings().isDefault, isTrue);
    });

    test('negative flips black and white', () {
      final m = const ImageViewSettings(inverted: true).colorMatrix();
      // out = scale * in + offset: black (0) must become white (255).
      expect(m[0] * 0 + m[4], closeTo(255, 0.01));
      expect(m[0] * 255 + m[4], closeTo(0, 0.01));
    });

    test('contrast keeps mid-grey where it is', () {
      final m = const ImageViewSettings(contrast: 0.8).colorMatrix();
      expect(m[0] * 127.5 + m[4], closeTo(127.5, 0.01));
    });

    test('survives a round trip through JSON', () {
      const settings = ImageViewSettings(brightness: 0.4, contrast: -0.2, inverted: true);
      final decoded = ImageViewSettings.decode(settings.encode());
      expect(decoded.brightness, closeTo(0.4, 0.0001));
      expect(decoded.contrast, closeTo(-0.2, 0.0001));
      expect(decoded.inverted, isTrue);
    });

    test('bad JSON decodes to the default instead of throwing', () {
      expect(ImageViewSettings.decode('not json').isDefault, isTrue);
      expect(ImageViewSettings.decode(null).isDefault, isTrue);
    });
  });

  group('annotations', () {
    test('the new tools survive a round trip', () {
      final shapes = [
        const AnnotationShape(
          tool: AnnotationTool.implant,
          points: [Offset(0.1, 0.2), Offset(0.1, 0.5)],
          colorHex: '#0A84FF',
          implantWidthMm: 4,
          implantLengthMm: 11.5,
        ),
        const AnnotationShape(
          tool: AnnotationTool.text,
          points: [Offset(0.3, 0.3), Offset(0.4, 0.4)],
          colorHex: '#FF3B30',
          text: 'caries',
        ),
        const AnnotationShape(
          tool: AnnotationTool.canal,
          points: [Offset(0, 0.8), Offset(1, 0.8)],
          colorHex: '#FFD60A',
        ),
      ];
      final decoded = decodeAnnotations(encodeAnnotations(shapes));
      expect(decoded.map((s) => s.tool).toList(), [
        AnnotationTool.implant,
        AnnotationTool.text,
        AnnotationTool.canal,
      ]);
      expect(decoded.first.implantWidthMm, 4);
      expect(decoded.first.implantLengthMm, 11.5);
      expect(decoded[1].text, 'caries');
    });

    test('annotations saved by older versions still load', () {
      const old = '[{"tool":"measurement","points":[[0.1,0.1],[0.2,0.2]],"color":"#FF3B30"}]';
      final decoded = decodeAnnotations(old);
      expect(decoded.single.tool, AnnotationTool.measurement);
      expect(decoded.single.text, isNull);
    });

    test('an unknown tool decodes as freehand rather than throwing', () {
      const future = '[{"tool":"hologram","points":[[0,0],[1,1]],"color":"#FFFFFF"}]';
      expect(decodeAnnotations(future).single.tool, AnnotationTool.freehand);
    });
  });

  group('DICOM scale', () {
    test('reads the pixel spacing out of the bundled x-ray', () {
      final dataset = const DicomParser()
          .parse(File('assets/sample/sample_xray.dcm').readAsBytesSync());
      expect(dataset.info.pixelSpacingMm, closeTo(0.15, 0.0001));
      expect(dataset.info.instanceNumber, 124);
    });

    test('a file without pixel spacing reports none', () {
      final dataset = const DicomParser()
          .parse(File('test/fixtures/sample_uncompressed.dcm').readAsBytesSync());
      expect(dataset.info.pixelSpacingMm, isNull);
    });
  });
}
