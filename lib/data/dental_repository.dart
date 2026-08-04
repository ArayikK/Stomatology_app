import '../models/patient.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';
import 'app_database.dart';

class DentalRepository {
  DentalRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<List<Patient>> getPatients() async {
    final db = await _database.database;
    final rows = await db.query('patients', orderBy: 'last_name, first_name');
    return rows.map(Patient.fromMap).toList();
  }

  Future<Patient> addPatient(String firstName, String lastName) async {
    final db = await _database.database;
    final patient = Patient(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      createdAt: DateTime.now(),
    );
    final id = await db.insert('patients', patient.toMap());
    return patient.copyWith(id: id);
  }

  Future<void> deletePatient(int patientId) async {
    final db = await _database.database;
    await db.delete('patients', where: 'id = ?', whereArgs: [patientId]);
    await db.delete(
      'tooth_notes',
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    await db.delete(
      'tooth_images',
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
  }

  /// Tooth numbers (1-32) that have at least one note or image for this patient.
  Future<Set<int>> getTeethWithHistory(int patientId) async {
    final db = await _database.database;
    final noteRows = await db.query(
      'tooth_notes',
      columns: ['DISTINCT tooth_number'],
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    final imageRows = await db.query(
      'tooth_images',
      columns: ['DISTINCT tooth_number'],
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    final result = <int>{};
    for (final row in noteRows) {
      result.add(row['tooth_number'] as int);
    }
    for (final row in imageRows) {
      result.add(row['tooth_number'] as int);
    }
    return result;
  }

  Future<List<ToothNote>> getNotes(int patientId, int toothNumber) async {
    final db = await _database.database;
    final rows = await db.query(
      'tooth_notes',
      where: 'patient_id = ? AND tooth_number = ?',
      whereArgs: [patientId, toothNumber],
      orderBy: 'created_at DESC',
    );
    return rows.map(ToothNote.fromMap).toList();
  }

  Future<ToothNote> addNote(int patientId, int toothNumber, String text) async {
    final db = await _database.database;
    final now = DateTime.now();
    final note = ToothNote(
      patientId: patientId,
      toothNumber: toothNumber,
      text: text.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert('tooth_notes', note.toMap());
    return note.copyWith(id: id);
  }

  Future<void> updateNote(ToothNote note, String newText) async {
    final db = await _database.database;
    final updated = note.copyWith(text: newText.trim(), updatedAt: DateTime.now());
    await db.update(
      'tooth_notes',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(int noteId) async {
    final db = await _database.database;
    await db.delete('tooth_notes', where: 'id = ?', whereArgs: [noteId]);
  }

  Future<List<ToothImage>> getImages(int patientId, int toothNumber) async {
    final db = await _database.database;
    final rows = await db.query(
      'tooth_images',
      where: 'patient_id = ? AND tooth_number = ?',
      whereArgs: [patientId, toothNumber],
      orderBy: 'created_at DESC',
    );
    return rows.map(ToothImage.fromMap).toList();
  }

  Future<ToothImage> addImage(
    int patientId,
    int toothNumber,
    String filePath, {
    String? originalDicomPath,
  }) async {
    final db = await _database.database;
    final image = ToothImage(
      patientId: patientId,
      toothNumber: toothNumber,
      filePath: filePath,
      originalDicomPath: originalDicomPath,
      createdAt: DateTime.now(),
    );
    final id = await db.insert('tooth_images', image.toMap());
    return ToothImage(
      id: id,
      patientId: patientId,
      toothNumber: toothNumber,
      filePath: filePath,
      originalDicomPath: originalDicomPath,
      createdAt: image.createdAt,
    );
  }

  Future<void> deleteImage(int imageId) async {
    final db = await _database.database;
    await db.delete('tooth_images', where: 'id = ?', whereArgs: [imageId]);
  }

  /// Inserts a few sample patients with per-tooth notes on first run, so the
  /// chart has something to show out of the box. No-ops if any patient
  /// already exists.
  Future<void> seedSampleDataIfEmpty() async {
    final existing = await getPatients();
    if (existing.isNotEmpty) return;

    for (final seed in _sampleSeed) {
      final patient = await addPatient(seed.firstName, seed.lastName);
      for (final note in seed.notes) {
        await addNote(patient.id!, note.toothNumber, note.text);
      }
    }
  }
}

class _SeedNote {
  const _SeedNote(this.toothNumber, this.text);
  final int toothNumber;
  final String text;
}

class _SeedPatient {
  const _SeedPatient(this.firstName, this.lastName, this.notes);
  final String firstName;
  final String lastName;
  final List<_SeedNote> notes;
}

const _sampleSeed = [
  _SeedPatient('Anna', 'Petrosyan', [
    _SeedNote(
      3,
      'Deep cavity on the occlusal surface, cleaned and filled with composite resin. No sensitivity reported at follow-up.',
    ),
    _SeedNote(
      14,
      'Root canal treatment completed over two visits. Crown placement recommended within the next month to protect the tooth.',
    ),
    _SeedNote(
      30,
      'Early-stage decay spotted on routine check-up. Watching for progression; no treatment yet, re-evaluate in 6 months.',
    ),
  ]),
  _SeedPatient('David', 'Grigoryan', [
    _SeedNote(
      8,
      'Chipped central incisor from a minor accident, repaired with composite bonding. Advised to avoid biting hard objects.',
    ),
    _SeedNote(
      19,
      'Large cavity between molars, filled after local anesthesia. Mild sensitivity to cold expected for 1-2 weeks.',
    ),
  ]),
  _SeedPatient('Mariam', 'Sargsyan', [
    _SeedNote(
      2,
      'Severely decayed wisdom tooth extracted. Socket healing normally, follow-up scheduled in 2 weeks.',
    ),
    _SeedNote(
      15,
      'Crown fitted after previous root canal therapy. Bite adjusted and polished; patient reports no discomfort.',
    ),
    _SeedNote(
      31,
      'Impacted wisdom tooth, mildly symptomatic. Extraction recommended, patient scheduling for next visit.',
    ),
  ]),
];
