import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stom/models/annotation_shape.dart';
import 'package:stom/models/image_view_settings.dart';
import 'package:stom/models/tooth_image.dart';
import 'package:stom/screens/image_annotation_screen.dart';
import 'package:stom/screens/image_compare_screen.dart';
import 'package:stom/widgets/annotated_image.dart';

/// Phone sizes the screens have to survive: a modern tall phone and a small
/// old one, where a crowded tool bar would overflow first.
const List<Size> _viewports = [Size(390, 844), Size(360, 640)];

late File _imageFile;
late Directory _tempDir;

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumping has to happen inside [WidgetTester.runAsync]: decoding a real
/// file goes through actual IO, which the fake async clock of a normal pump
/// never lets finish - the screen would sit on its loading spinner forever.
Future<void> _settleWithImage(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  // Then let any route/fade animation run out. pumpAndSettle can't be used
  // while a loading spinner is on screen - it never settles.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Waits until [finder] appears, pumping real time as well as frames: with
/// several tests in one file the decode can land a few frames later than a
/// single test would suggest.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  double? mmPerPixel,
  List<AnnotationShape> shapes = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ImageAnnotationScreen(
        imageFile: _imageFile,
        initialShapes: shapes,
        mmPerPixel: mmPerPixel,
      ),
    ),
  );
  await _settleWithImage(tester);
}

void main() {
  setUpAll(() {
    _tempDir = Directory.systemTemp.createTempSync('stom_screens_');
    _imageFile = File('${_tempDir.path}/xray.png')
      ..writeAsBytesSync(File('test/fixtures/sample_render_source.png').readAsBytesSync());
  });

  setUp(() {
    // Each test decodes the same file; a cached entry from a finished test
    // holds an image that has already been disposed, and the next screen
    // then waits for a frame that never comes.
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  tearDownAll(() {
    // Windows keeps the decoded file handle open for a moment; a leftover
    // temp folder must not fail the suite.
    try {
      if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('annotation editor', () {
    for (final viewport in _viewports) {
      testWidgets('fits a ${viewport.width.toInt()}x${viewport.height.toInt()} screen',
          (tester) async {
        _useViewport(tester, viewport);
        await _pumpEditor(tester);

        // Every tool has to be reachable, and nothing may overflow.
        for (final label in ['Move', 'Draw', 'Line', 'Measure', 'Angle', 'Label', 'Implant', 'Canal', 'Scale']) {
          expect(find.text(label), findsOneWidget, reason: '$label on $viewport');
        }
      });
    }

    testWidgets('drawing a measurement keeps it, and SAVE returns it', (tester) async {
      _useViewport(tester, _viewports.first);
      AnnotationEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<AnnotationEditResult>(
                    MaterialPageRoute(
                      builder: (context) => ImageAnnotationScreen(
                        imageFile: _imageFile,
                        initialShapes: const [],
                        mmPerPixel: 0.15,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settleWithImage(tester);
      await _waitFor(tester, find.byType(AnnotatedImageView));

      await tester.tap(find.text('Measure'));
      await tester.pump();
      final canvas = tester.getCenter(find.byType(AnnotatedImageView));
      await tester.dragFrom(canvas - const Offset(40, 40), const Offset(80, 80));
      await tester.pump();

      await tester.tap(find.text('SAVE'));
      await _settleWithImage(tester);

      expect(result, isNotNull);
      expect(result!.shapes, hasLength(1));
      expect(result!.shapes.single.tool, AnnotationTool.measurement);
      expect(result!.mmPerPixel, 0.15);
    });

    testWidgets('the implant tool offers diameters and lengths', (tester) async {
      _useViewport(tester, _viewports.first);
      await _pumpEditor(tester, mmPerPixel: 0.15);

      await tester.tap(find.text('Implant'));
      await tester.pump();

      expect(find.byType(DropdownButton<double>), findsNWidgets(2));
      expect(find.textContaining('3.5 mm'), findsWidgets);
    });

    testWidgets('says when an image has no scale', (tester) async {
      _useViewport(tester, _viewports.first);
      await _pumpEditor(tester);

      await tester.tap(find.text('Measure'));
      await tester.pump();

      expect(find.textContaining('No scale on this image'), findsOneWidget);
    });

    testWidgets('a calibrated image promises millimetres', (tester) async {
      _useViewport(tester, _viewports.first);
      await _pumpEditor(tester, mmPerPixel: 0.15);

      await tester.tap(find.text('Measure'));
      await tester.pump();

      expect(find.textContaining('shown in millimetres'), findsOneWidget);
    });

    testWidgets('the image panel switches to brightness and contrast', (tester) async {
      _useViewport(tester, _viewports.first);
      await _pumpEditor(tester);

      await tester.tap(find.text('Image'));
      await tester.pump();

      expect(find.byType(Slider), findsNWidgets(2));
      expect(find.text('Negative'), findsOneWidget);
    });

    testWidgets('undo removes the last shape', (tester) async {
      _useViewport(tester, _viewports.first);
      await _pumpEditor(
        tester,
        shapes: const [
          AnnotationShape(
            tool: AnnotationTool.line,
            points: [Offset(0.1, 0.1), Offset(0.4, 0.4)],
            colorHex: '#FF3B30',
          ),
        ],
      );

      final undo = find.ancestor(
        of: find.byIcon(Icons.undo),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
      await tester.tap(undo);
      await tester.pump();
      expect(tester.widget<IconButton>(undo).onPressed, isNull);
    });
  });

  group('compare screen', () {
    testWidgets('shows both images with their dates and a zoom link', (tester) async {
      _useViewport(tester, _viewports.first);
      final image = ToothImage(
        id: 1,
        patientId: 1,
        toothNumber: 14,
        filePath: _imageFile.path,
        viewSettingsJson: const ImageViewSettings(contrast: 0.2).encode(),
        createdAt: DateTime(2026, 3, 4),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ImageCompareScreen(left: image, right: image),
        ),
      );
      await _settleWithImage(tester);

      expect(find.textContaining('Before'), findsOneWidget);
      expect(find.textContaining('After'), findsOneWidget);
      expect(find.textContaining('04.03.2026'), findsNWidgets(2));
      expect(find.byIcon(Icons.link), findsOneWidget);
    });
  });
}
