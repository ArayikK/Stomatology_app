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
        await db.execute(
          'CREATE INDEX idx_notes_patient_tooth ON tooth_notes (patient_id, tooth_number)',
        );
        await db.execute(
          'CREATE INDEX idx_images_patient_tooth ON tooth_images (patient_id, tooth_number)',
        );
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }
}
