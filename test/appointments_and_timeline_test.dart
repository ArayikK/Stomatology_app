import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stom/data/app_database.dart';
import 'package:stom/data/backend_sync_service.dart';
import 'package:stom/data/dental_repository.dart';
import 'package:stom/models/patient.dart';
import 'package:stom/screens/appointments_screen.dart';
import 'package:stom/screens/patient_profile_screen.dart';

/// A phone-sized surface: the dialogs size themselves off the screen width,
/// and it was on a phone that the chip labels were being cut off.
const Size _phoneSize = Size(430, 920);

void main() {
  late DentalRepository repository;
  late BackendSyncService syncService;
  late Map<String, Patient> patients;

  setUpAll(() async {
    sqfliteFfiInit();
    // The no-isolate factory, not the default one: testWidgets runs in a fake
    // async zone that never pumps a background isolate's messages, so every
    // database call would deadlock.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  // Fixtures are built here rather than inside the tests because a test body
  // runs in fake async, where a real database call may never complete.
  setUp(() async {
    final dbPath = p.join(await databaseFactory.getDatabasesPath(), 'stom_dental.db');
    await AppDatabase.instance.close();
    await databaseFactory.deleteDatabase(dbPath);

    repository = DentalRepository(database: AppDatabase.instance);
    syncService = BackendSyncService(
      repository: repository,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    patients = {
      for (final name in const [
        ['Anna', 'Petrosyan'],
        ['David', 'Grigoryan'],
        ['Mariam', 'Sargsyan'],
      ])
        name.last: await repository.addPatient(name.first, name.last),
    };
  });

  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('appointment form shows every quick time in full', (tester) async {
    setPhoneSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentsScreen(repository: repository, syncService: syncService),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New appointment'));
    await tester.pumpAndSettle();

    // A clipped "09:3" still matches find.text, so what's checked is that each
    // label is painted inside its chip rather than running past its edge.
    for (final label in [
      '09:00', '09:30', '10:00', '17:00', // time slots
      'Today', 'Tomorrow', 'Next week', // quick days
    ]) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: '$label should be on screen');
      final chip = find.ancestor(of: finder, matching: find.byType(ChoiceChip));
      expect(
        tester.getRect(finder).width,
        lessThanOrEqualTo(tester.getRect(chip).width),
        reason: '$label is wider than its chip, so it gets cut off',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a patient can be searched for, and added, from the appointment form',
      (tester) async {
    setPhoneSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentsScreen(repository: repository, syncService: syncService),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New appointment'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    // The picker's own search box - the form underneath has fields too.
    final searchField = find
        .descendant(of: find.byType(AlertDialog).last, matching: find.byType(TextField))
        .first;

    // Searching narrows the list rather than making the dentist scroll it.
    await tester.enterText(searchField, 'grig');
    await tester.pumpAndSettle();
    expect(find.text('David Grigoryan'), findsOneWidget);
    expect(find.text('Anna Petrosyan'), findsNothing);

    // A patient who isn't on file yet can be created without leaving the form,
    // and the name already typed carries over.
    await tester.enterText(searchField, 'Nare Hakobyan');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add "Nare Hakobyan" as a new patient'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Nare'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Hakobyan'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Picked into the form, and a real patient record from now on.
    expect(find.text('Nare Hakobyan'), findsOneWidget);
    final stored = await tester.runAsync(
      () => repository.searchPatients('Hakobyan'),
    );
    expect(stored!.single.fullName, 'Nare Hakobyan');
  });

  testWidgets('treatment timeline entries can be added and deleted', (tester) async {
    setPhoneSurface(tester);
    final patient = patients['Sargsyan']!;

    await tester.pumpWidget(
      MaterialApp(
        home: PatientProfileScreen(
          repository: repository,
          syncService: syncService,
          patient: patient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Treatment Timeline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No treatment history'), findsOneWidget);

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cleaning'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What was done'),
      'Full scale and polish, no bleeding on probing.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Full scale and polish'), findsOneWidget);
    final notes = await tester.runAsync(
      () => repository.getAllNotesForPatient(patient.id!),
    );
    expect(notes!.single.isGeneral, isTrue);

    await tester.tap(find.byTooltip('Entry options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    final remaining = await tester.runAsync(
      () => repository.getAllNotesForPatient(patient.id!),
    );
    expect(remaining, isEmpty);
  });

  testWidgets('medical history saves what was typed', (tester) async {
    setPhoneSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: PatientProfileScreen(
          repository: repository,
          syncService: syncService,
          patient: patients['Petrosyan']!,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing to save until something is actually edited.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes')).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).first, 'Penicillin');
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(
      () => repository.searchPatients('Petrosyan'),
    );
    expect(saved!.single.allergies, 'Penicillin');
    expect(find.text('Everything here is saved.'), findsOneWidget);
  });
}
