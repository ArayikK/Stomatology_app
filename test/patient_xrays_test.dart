import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stom/data/app_database.dart';
import 'package:stom/data/backend_sync_service.dart';
import 'package:stom/data/dental_repository.dart';
import 'package:stom/models/patient.dart';
import 'package:stom/models/tooth_note.dart';
import 'package:stom/screens/image_viewer_screen.dart';
import 'package:stom/screens/patient_xrays_tab.dart';
import 'package:stom/screens/tooth_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DentalRepository repository;
  late BackendSyncService syncService;
  late Patient patient;
  late Directory tempDir;
  late File imageFile;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('stom_patient_xrays_').path,
    );
  });

  setUp(() async {
    final dbPath = p.join(await databaseFactory.getDatabasesPath(), 'stom_dental.db');
    await AppDatabase.instance.close();
    await databaseFactory.deleteDatabase(dbPath);
    repository = DentalRepository(database: AppDatabase.instance);
    syncService = BackendSyncService(
      repository: repository,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    patient = await repository.addPatient('Anna', 'Petrosyan');

    tempDir = Directory.systemTemp.createTempSync('stom_patient_xrays_files_');
    imageFile = File(p.join(tempDir.path, 'pano.png'))
      ..writeAsBytesSync(File('test/fixtures/sample_render_source.png').readAsBytesSync());

    imageCache.clear();
    imageCache.clearLiveImages();
    SharedPreferences.setMockInitialValues({'stom_tour_enabled': false});
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PatientXraysTab(
          repository: repository,
          syncService: syncService,
          patient: patient,
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  test('patient-level images are stored apart from any tooth', () async {
    await repository.addImage(patient.id!, kGeneralToothNumber, imageFile.path);
    await repository.addImage(patient.id!, 14, imageFile.path);

    final general = await repository.getImages(patient.id!, kGeneralToothNumber);
    final tooth = await repository.getImages(patient.id!, 14);

    expect(general, hasLength(1));
    expect(tooth, hasLength(1));
    // Both still belong to the patient, so a report or a sync sees them all.
    expect(await repository.getPatientImages(patient.id!), hasLength(2));
  });

  testWidgets('explains itself when the patient has no images yet', (tester) async {
    await pumpTab(tester);

    expect(find.textContaining('No images for this patient yet'), findsOneWidget);
    expect(find.textContaining('Images of a single tooth'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add image'), findsOneWidget);
  });

  testWidgets('shows the patient images with dates, and marks a CBCT series',
      (tester) async {
    await repository.addImage(
      patient.id!,
      kGeneralToothNumber,
      imageFile.path,
      pixelSpacingMm: 0.15,
    );
    await repository.addImage(
      patient.id!,
      kGeneralToothNumber,
      imageFile.path,
      seriesDir: tempDir.path,
      sliceCount: 240,
    );

    await pumpTab(tester);

    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('240 slices'), findsOneWidget);
    final today = DateTime.now();
    final date = '${today.day.toString().padLeft(2, '0')}.'
        '${today.month.toString().padLeft(2, '0')}.${today.year}';
    expect(find.text(date), findsNWidgets(2));
  });

  testWidgets('a tooth image does not show up in the patient tab', (tester) async {
    await repository.addImage(patient.id!, 14, imageFile.path);

    await pumpTab(tester);

    expect(find.textContaining('No images for this patient yet'), findsOneWidget);
  });

  testWidgets('the viewer opens with brightness/contrast already showing',
      (tester) async {
    final image = await repository.addImage(
      patient.id!,
      kGeneralToothNumber,
      imageFile.path,
      pixelSpacingMm: 0.15,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerScreen(
          repository: repository,
          syncService: syncService,
          image: image,
          siblings: [image],
          patient: patient,
          notes: const [],
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // No tap needed: the panel is part of the first screen the dentist sees.
    expect(find.text('Negative'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));

    // And it can still be folded away to give the image the whole screen.
    await tester.tap(find.byTooltip('Brightness & contrast'));
    await tester.pump();
    expect(find.text('Negative'), findsNothing);
  });

  testWidgets('the "add" tile is exactly the same square as a thumbnail',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await repository.addImage(patient.id!, 14, imageFile.path);

    await tester.pumpWidget(
      MaterialApp(
        home: ToothDetailScreen(
          repository: repository,
          syncService: syncService,
          patientId: patient.id!,
          toothNumber: 14,
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    Size tileSizeOf(Finder inner) => tester.getSize(
          find.ancestor(of: inner, matching: find.byType(ClipRRect)).first,
        );

    final thumbnail = tileSizeOf(find.byType(Image).first);
    final placeholder = tileSizeOf(find.byIcon(Icons.add_a_photo_outlined));

    expect(placeholder, thumbnail);
    expect(thumbnail, const Size(96, 96));
    // Both sit on the same line, so the strip reads as one row of squares.
    expect(
      tester.getTopLeft(find.byType(Image).first).dy,
      tester.getTopLeft(find.byIcon(Icons.add_a_photo_outlined)).dy - 36,
    );
  });

  test('general notes and patient images share the same general slot', () async {
    await repository.addNote(patient.id!, kGeneralToothNumber, 'Whole-mouth cleaning');
    await repository.addImage(patient.id!, kGeneralToothNumber, imageFile.path);

    final notes = await repository.getNotes(patient.id!, kGeneralToothNumber);
    final images = await repository.getImages(patient.id!, kGeneralToothNumber);

    expect(notes.single.text, 'Whole-mouth cleaning');
    expect(images, hasLength(1));
  });
}
