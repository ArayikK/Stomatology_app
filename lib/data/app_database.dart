import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class AppDatabase {
  AppDatabase._() {
    // sqflite has no native web implementation; route it through the
    // IndexedDB-backed driver when running in a browser.
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
  }
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await _open();
    _db = db;
    return db;
  }

  Future<Database> _open() async {
    final path = kIsWeb
        ? 'stom_dental.db'
        : p.join(await getDatabasesPath(), 'stom_dental.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE patients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_name TEXT NOT NULL,
            last_name TEXT NOT NULL,
            allergies TEXT,
            medications TEXT,
            medical_notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE tooth_notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id INTEGER NOT NULL,
            tooth_number INTEGER NOT NULL,
            text TEXT NOT NULL,
            category TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE tooth_note_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            category TEXT,
            edited_at TEXT NOT NULL,
            FOREIGN KEY (note_id) REFERENCES tooth_notes (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE tooth_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id INTEGER NOT NULL,
            tooth_number INTEGER NOT NULL,
            file_path TEXT NOT NULL,
            original_dicom_path TEXT,
            role TEXT,
            paired_image_id INTEGER,
            annotations_json TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_notes_patient_tooth ON tooth_notes (patient_id, tooth_number)',
        );
        await db.execute(
          'CREATE INDEX idx_images_patient_tooth ON tooth_images (patient_id, tooth_number)',
        );
        await db.execute(
          'CREATE INDEX idx_note_history_note ON tooth_note_history (note_id)',
        );
        await db.execute('''
          CREATE TABLE patient_relationships (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id INTEGER NOT NULL,
            related_patient_id INTEGER NOT NULL,
            relationship_type TEXT NOT NULL,
            FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE,
            FOREIGN KEY (related_patient_id) REFERENCES patients (id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_relationships_patient ON patient_relationships (patient_id)',
        );
        await db.execute('''
          CREATE TABLE appointments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id INTEGER NOT NULL,
            date_time TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            notes TEXT NOT NULL,
            reminder_minutes_before INTEGER,
            created_at TEXT NOT NULL,
            FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_appointments_date ON appointments (date_time)',
        );
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }
}
