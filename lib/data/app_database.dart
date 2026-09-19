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

  /// Bumped to 2 when note history, family links and appointments were added.
  /// Early builds shipped those tables under version 1, so the version number
  /// alone can't be trusted - [ensureSchema] repairs whatever is missing.
  static const int _schemaVersion = 2;

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await _open();
    _db = db;
    return db;
  }

  /// Closes the connection, if one is open. The next access reopens it.
  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  Future<Database> _open() async {
    final path = kIsWeb
        ? 'stom_dental.db'
        : p.join(await getDatabasesPath(), 'stom_dental.db');
    return openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) => ensureSchema(db),
      onUpgrade: (db, oldVersion, newVersion) => ensureSchema(db),
      onDowngrade: (db, oldVersion, newVersion) => ensureSchema(db),
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onOpen: (db) async {
        // Safety net for databases that were left half-built: tables were
        // added in later releases without the version ever being bumped, so a
        // device that installed one of those builds still reports version 1
        // (or 2) while missing tables. One cheap query per launch catches it.
        final found = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN "
            "('patients', 'tooth_notes', 'tooth_note_history', 'tooth_images', "
            "'patient_relationships', 'appointments')",
          ),
        );
        if (found != 6) await ensureSchema(db);
      },
    );
  }

  /// Creates every table, column and index that is missing, leaving existing
  /// data untouched. Safe to run on a brand new database and on any older
  /// one, as often as needed. Public so the migration test can point it at a
  /// database built with an old schema.
  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS patients (
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
      CREATE TABLE IF NOT EXISTS tooth_notes (
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
      CREATE TABLE IF NOT EXISTS tooth_note_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        text TEXT NOT NULL,
        category TEXT,
        edited_at TEXT NOT NULL,
        FOREIGN KEY (note_id) REFERENCES tooth_notes (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tooth_images (
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS patient_relationships (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL,
        related_patient_id INTEGER NOT NULL,
        relationship_type TEXT NOT NULL,
        FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE,
        FOREIGN KEY (related_patient_id) REFERENCES patients (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS appointments (
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

    // Columns that arrived after a table already shipped. ALTER TABLE can't
    // add a NOT NULL column without a default, so the ones the app treats as
    // required are added as nullable and backfilled.
    await _addColumnIfMissing(db, 'patients', 'allergies', 'TEXT');
    await _addColumnIfMissing(db, 'patients', 'medications', 'TEXT');
    await _addColumnIfMissing(db, 'patients', 'medical_notes', 'TEXT');
    await _addColumnIfMissing(db, 'tooth_notes', 'category', 'TEXT');
    if (await _addColumnIfMissing(db, 'tooth_notes', 'updated_at', 'TEXT')) {
      await db.execute(
        'UPDATE tooth_notes SET updated_at = created_at WHERE updated_at IS NULL',
      );
    }
    await _addColumnIfMissing(db, 'tooth_images', 'original_dicom_path', 'TEXT');
    await _addColumnIfMissing(db, 'tooth_images', 'role', 'TEXT');
    await _addColumnIfMissing(db, 'tooth_images', 'paired_image_id', 'INTEGER');
    await _addColumnIfMissing(db, 'tooth_images', 'annotations_json', 'TEXT');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_patient_tooth ON tooth_notes (patient_id, tooth_number)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_images_patient_tooth ON tooth_images (patient_id, tooth_number)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_history_note ON tooth_note_history (note_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_relationships_patient ON patient_relationships (patient_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments (date_time)',
    );
  }

  /// Returns true when the column was actually added.
  static Future<bool> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (exists) return false;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    return true;
  }
}
