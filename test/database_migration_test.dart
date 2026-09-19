import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stom/data/app_database.dart';

/// The schema the first released builds created. Later releases added tables
/// and columns but left `version: 1`, so upgrading over one of these installs
/// used to leave the app querying tables that were never created.
Future<Database> _openLegacyDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE patients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      first_name TEXT NOT NULL,
      last_name TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE tooth_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL,
      tooth_number INTEGER NOT NULL,
      text TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE tooth_images (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL,
      tooth_number INTEGER NOT NULL,
      file_path TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
    )
  ''');
  return db;
}

Future<Set<String>> _tables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return {for (final row in rows) row['name'] as String};
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return {for (final row in rows) row['name'] as String};
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('repairs a database created by an early build', () async {
    final db = await _openLegacyDatabase();
    addTearDown(db.close);
    await db.insert('patients', {
      'first_name': 'Old',
      'last_name': 'Install',
      'created_at': '2026-01-01T09:00:00.000',
    });
    await db.insert('tooth_notes', {
      'patient_id': 1,
      'tooth_number': 11,
      'text': 'Existing note',
      'created_at': '2026-01-01T09:00:00.000',
      'updated_at': '2026-01-01T09:00:00.000',
    });

    await AppDatabase.ensureSchema(db);

    expect(
      await _tables(db),
      containsAll([
        'patients',
        'tooth_notes',
        'tooth_note_history',
        'tooth_images',
        'patient_relationships',
        'appointments',
      ]),
    );
    expect(
      await _columns(db, 'patients'),
      containsAll(['allergies', 'medications', 'medical_notes']),
    );
    expect(await _columns(db, 'tooth_notes'), contains('category'));
    expect(
      await _columns(db, 'tooth_images'),
      containsAll([
        'original_dicom_path',
        'role',
        'paired_image_id',
        'annotations_json',
      ]),
    );

    // The dashboard query that used to throw "no such table: appointments".
    expect(await db.query('appointments'), isEmpty);

    // Existing rows survive untouched.
    final patients = await db.query('patients');
    expect(patients.single['first_name'], 'Old');
    final notes = await db.query('tooth_notes');
    expect(notes.single['text'], 'Existing note');
    expect(notes.single['category'], isNull);
  });

  test('is safe to run twice and on an up-to-date database', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await AppDatabase.ensureSchema(db);
    final afterFirst = await _tables(db);
    await AppDatabase.ensureSchema(db);

    expect(await _tables(db), afterFirst);
    expect(await db.query('appointments'), isEmpty);
  });

  test('backfills updated_at when the column is missing', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE tooth_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL,
        tooth_number INTEGER NOT NULL,
        text TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.insert('tooth_notes', {
      'patient_id': 1,
      'tooth_number': 11,
      'text': 'No updated_at yet',
      'created_at': '2026-01-01T09:00:00.000',
    });

    await AppDatabase.ensureSchema(db);

    final notes = await db.query('tooth_notes');
    expect(notes.single['updated_at'], '2026-01-01T09:00:00.000');
  });
}
