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
import 'package:stom/main.dart';
import 'package:stom/models/patient.dart';
import 'package:stom/screens/patient_chart_screen.dart';

/// The short ones are the point: that is where tooltip placement fails.
const List<Size> _viewports = [
  Size(390, 844),
  Size(375, 667),
  Size(360, 800),
  Size(360, 640),
];

/// Greeting, stats, today's schedule, recently seen, backup, menu.
const int _homeStepCount = 6;

void main() {
  late DentalRepository repository;
  late BackendSyncService syncService;
  late Patient patient;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // Test files run in parallel; a private folder keeps this file's
    // database from being locked by another file's.
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('stom_test_').path,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'stom_intro_seen': true,
      'stom_tour_enabled': true,
    });
    final dbPath = p.join(await databaseFactory.getDatabasesPath(), 'stom_dental.db');
    await AppDatabase.instance.close();
    await databaseFactory.deleteDatabase(dbPath);
    repository = DentalRepository(database: AppDatabase.instance);
    syncService = BackendSyncService(
      repository: repository,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    patient = await repository.addPatient('Anna', 'Petrosyan');
  });

  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    // Test fonts render every glyph as a wide square; scale them back down
    // so line counts are close to what a real phone shows.
    tester.platformDispatcher.textScaleFactorTestValue = 0.72;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Runs [body] while collecting every framework error except layout
  /// overflow (the test font makes real screens overflow where phones don't),
  /// then fails on anything that was collected.
  Future<void> ignoringOverflow(Future<void> Function() body) async {
    final original = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = (details) {
      if (!details.toString().contains('overflowed')) errors.add(details);
    };
    try {
      await body();
    } finally {
      FlutterError.onError = original;
    }
    expect(errors, isEmpty, reason: errors.map((e) => e.toString()).join('\n'));
  }

  /// Walks every step, checking each tooltip is fully on screen.
  Future<void> walkTour(WidgetTester tester, int stepCount, Size viewport) async {
    for (var i = 1; i <= stepCount; i++) {
      final label = find.text('STEP $i OF $stepCount');
      expect(label, findsOneWidget, reason: 'step $i on $viewport');

      final card = find.ancestor(of: label, matching: find.byType(Container)).first;
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(0), reason: 'step $i clipped at the top on $viewport');
      expect(
        rect.bottom,
        lessThanOrEqualTo(viewport.height),
        reason: 'step $i clipped at the bottom on $viewport',
      );

      final isLast = i == stepCount;
      final button = find.widgetWithText(FilledButton, isLast ? 'Finish' : 'Next');
      expect(button, findsOneWidget, reason: 'step $i button on $viewport');
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('STEP '), findsNothing);
  }

  for (final viewport in _viewports) {
    testWidgets('home tour fits on a ${viewport.width.toInt()}x${viewport.height.toInt()} screen',
        (tester) async {
      useViewport(tester, viewport);
      await ignoringOverflow(() async {
        await tester.pumpWidget(StomApp(repository: repository, syncService: syncService));
        await tester.pumpAndSettle();
        await walkTour(tester, _homeStepCount, viewport);
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('stom_tour_done_home'), isTrue);
    });
  }

  testWidgets('first launch: "Take the tour" leads into the home tour', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, _viewports.first);
    await ignoringOverflow(() async {
      await tester.pumpWidget(
        StomApp(repository: repository, syncService: syncService, showIntro: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take the tour'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1 OF $_homeStepCount'), findsOneWidget);
    });
  });

  testWidgets('"Skip tour" closes it and turns off the other screens\' tours', (tester) async {
    useViewport(tester, _viewports.first);
    await ignoringOverflow(() async {
      await tester.pumpWidget(StomApp(repository: repository, syncService: syncService));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip tour'));
      await tester.pumpAndSettle();
      expect(find.textContaining('STEP '), findsNothing);
    });

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('stom_tour_enabled'), isFalse);
  });

  testWidgets('"Skip for now" opens the dashboard with no tour', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, _viewports.first);
    await ignoringOverflow(() async {
      await tester.pumpWidget(
        StomApp(repository: repository, syncService: syncService, showIntro: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(find.text('Stom'), findsOneWidget);
      expect(find.textContaining('STEP '), findsNothing);
    });
  });

  testWidgets('chart tour includes the allergy step only when there are allergies',
      (tester) async {
    useViewport(tester, _viewports.last);
    await repository.updatePatientMedicalInfo(
      patient.id!,
      allergies: 'Penicillin',
      medications: '',
      medicalNotes: '',
    );
    final withAllergies = (await repository.getPatients()).firstWhere((x) => x.id == patient.id);
    final noAllergies = await repository.addPatient('David', 'Grigoryan');

    await ignoringOverflow(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PatientChartScreen(
            repository: repository,
            syncService: syncService,
            patient: withAllergies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await walkTour(tester, 3, _viewports.last);
    });

    // Turn the chart tour back on to see it without the allergy banner.
    SharedPreferences.setMockInitialValues({'stom_tour_enabled': true});
    await ignoringOverflow(() async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: PatientChartScreen(
            repository: repository,
            syncService: syncService,
            patient: noAllergies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await walkTour(tester, 2, _viewports.last);
    });
  });
}
