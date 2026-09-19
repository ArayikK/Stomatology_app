import '../models/annotation_shape.dart';
import '../models/appointment.dart';
import '../models/note_category.dart';
import '../models/patient.dart';
import '../models/patient_relationship.dart';
import '../models/patient_summary.dart';
import '../models/relationship_type.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';
import '../models/tooth_note_history_entry.dart';
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

  /// Patients plus their treatment-history/last-activity facts, for the
  /// patient list's search/filter/sort.
  Future<List<PatientSummary>> getPatientSummaries() async {
    final db = await _database.database;
    final patients = await getPatients();

    final noteRows = await db.rawQuery(
      'SELECT patient_id, MAX(updated_at) AS last_activity FROM tooth_notes GROUP BY patient_id',
    );
    final imageRows = await db.rawQuery(
      'SELECT patient_id, MAX(created_at) AS last_activity FROM tooth_images GROUP BY patient_id',
    );

    final lastActivityByPatient = <int, DateTime>{};
    for (final row in [...noteRows, ...imageRows]) {
      final patientId = row['patient_id'] as int;
      final raw = row['last_activity'] as String?;
      if (raw == null) continue;
      final activity = DateTime.parse(raw);
      final existing = lastActivityByPatient[patientId];
      if (existing == null || activity.isAfter(existing)) {
        lastActivityByPatient[patientId] = activity;
      }
    }

    return [
      for (final patient in patients)
        PatientSummary(
          patient: patient,
          hasHistory: lastActivityByPatient.containsKey(patient.id),
          lastActivity: lastActivityByPatient[patient.id],
        ),
    ];
  }

  /// Name search for the patient pickers. A practice can have thousands of
  /// patients, so the filtering and the cap both happen in SQL rather than by
  /// loading every row into memory first.
  Future<List<Patient>> searchPatients(String query, {int limit = 50}) async {
    final db = await _database.database;
    final trimmed = query.trim();
    final rows = trimmed.isEmpty
        ? await db.query(
            'patients',
            orderBy: 'last_name, first_name',
            limit: limit,
          )
        : await db.rawQuery(
            '''
            SELECT * FROM patients
            WHERE first_name LIKE ?
               OR last_name LIKE ?
               OR (first_name || ' ' || last_name) LIKE ?
            ORDER BY last_name, first_name
            LIMIT ?
            ''',
            ['%$trimmed%', '%$trimmed%', '%$trimmed%', limit],
          );
    return rows.map(Patient.fromMap).toList();
  }

  /// How many patients exist in total, so a capped search result can say what
  /// it is a subset of.
  Future<int> countPatients() async {
    final db = await _database.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM patients');
    return (rows.first['count'] as int?) ?? 0;
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

  Future<void> updatePatientMedicalInfo(
    int patientId, {
    required String allergies,
    required String medications,
    required String medicalNotes,
  }) async {
    final db = await _database.database;
    await db.update(
      'patients',
      {
        'allergies': allergies.trim(),
        'medications': medications.trim(),
        'medical_notes': medicalNotes.trim(),
      },
      where: 'id = ?',
      whereArgs: [patientId],
    );
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

  /// Links two patients as related (e.g. family members). Stored as a row
  /// on each side so each patient's own record shows the relationship from
  /// their own point of view (spouse/spouse, parent/child, etc).
  Future<void> linkPatients(
    int patientId,
    int relatedPatientId,
    RelationshipType type,
  ) async {
    final db = await _database.database;
    await db.insert('patient_relationships', {
      'patient_id': patientId,
      'related_patient_id': relatedPatientId,
      'relationship_type': type.name,
    });
    await db.insert('patient_relationships', {
      'patient_id': relatedPatientId,
      'related_patient_id': patientId,
      'relationship_type': type.reciprocal.name,
    });
  }

  Future<void> unlinkPatients(int patientId, int relatedPatientId) async {
    final db = await _database.database;
    await db.delete(
      'patient_relationships',
      where: '(patient_id = ? AND related_patient_id = ?) OR (patient_id = ? AND related_patient_id = ?)',
      whereArgs: [patientId, relatedPatientId, relatedPatientId, patientId],
    );
  }

  Future<List<PatientRelationship>> getRelationships(int patientId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT patients.*, patient_relationships.relationship_type AS rel_type
      FROM patient_relationships
      JOIN patients ON patients.id = patient_relationships.related_patient_id
      WHERE patient_relationships.patient_id = ?
      ORDER BY patients.last_name, patients.first_name
      ''',
      [patientId],
    );
    return [
      for (final row in rows)
        PatientRelationship(
          relatedPatient: Patient.fromMap(row),
          type: RelationshipType.fromName(row['rel_type'] as String?),
        ),
    ];
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

  /// All notes for a patient across every tooth, newest first - the
  /// chronological treatment timeline.
  Future<List<ToothNote>> getAllNotesForPatient(int patientId) async {
    final db = await _database.database;
    final rows = await db.query(
      'tooth_notes',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ToothNote.fromMap).toList();
  }

  /// [createdAt] is what the treatment timeline sorts and dates entries by,
  /// so it can be backdated when a past treatment is recorded after the fact.
  Future<ToothNote> addNote(
    int patientId,
    int toothNumber,
    String text, {
    NoteCategory category = NoteCategory.other,
    DateTime? createdAt,
  }) async {
    final db = await _database.database;
    final now = DateTime.now();
    final note = ToothNote(
      patientId: patientId,
      toothNumber: toothNumber,
      text: text.trim(),
      category: category,
      createdAt: createdAt ?? now,
      updatedAt: now,
    );
    final id = await db.insert('tooth_notes', note.toMap());
    return note.copyWith(id: id);
  }

  Future<void> updateNote(
    ToothNote note,
    String newText, {
    NoteCategory? category,
    DateTime? createdAt,
  }) async {
    final db = await _database.database;
    // Snapshot the pre-edit state so it can be viewed or reverted to later.
    await db.insert('tooth_note_history', {
      'note_id': note.id,
      'text': note.text,
      'category': note.category.name,
      'edited_at': DateTime.now().toIso8601String(),
    });
    final updated = note.copyWith(
      text: newText.trim(),
      category: category,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
    await db.update(
      'tooth_notes',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<List<ToothNoteHistoryEntry>> getNoteHistory(int noteId) async {
    final db = await _database.database;
    final rows = await db.query(
      'tooth_note_history',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'edited_at DESC',
    );
    return rows.map(ToothNoteHistoryEntry.fromMap).toList();
  }

  /// Reverts a note to an earlier version. This is itself just an update,
  /// so it snapshots the note's current (about-to-be-replaced) state into
  /// history too - reverting is never a dead end, you can always go back.
  Future<void> revertNoteToHistoryEntry(ToothNote note, ToothNoteHistoryEntry entry) async {
    await updateNote(note, entry.text, category: entry.category);
  }

  /// Moves a note to another tooth (or to [kGeneralToothNumber] for an entry
  /// that isn't about one tooth). Separate from [updateNote] because it
  /// changes where the note lives rather than what it says, so it isn't a
  /// text edit worth snapshotting into history.
  Future<void> moveNoteToTooth(int noteId, int toothNumber) async {
    final db = await _database.database;
    await db.update(
      'tooth_notes',
      {'tooth_number': toothNumber},
      where: 'id = ?',
      whereArgs: [noteId],
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
    await unpairImage(imageId);
    await db.delete('tooth_images', where: 'id = ?', whereArgs: [imageId]);
  }

  /// Links two images of the same tooth as a before/after comparison pair.
  Future<void> pairImages({required int beforeImageId, required int afterImageId}) async {
    final db = await _database.database;
    await db.update(
      'tooth_images',
      {'role': ImageRole.before.name, 'paired_image_id': afterImageId},
      where: 'id = ?',
      whereArgs: [beforeImageId],
    );
    await db.update(
      'tooth_images',
      {'role': ImageRole.after.name, 'paired_image_id': beforeImageId},
      where: 'id = ?',
      whereArgs: [afterImageId],
    );
  }

  /// Clears the before/after link on both sides of the pair [imageId]
  /// belongs to, if any. Safe to call on an unpaired image (no-op).
  Future<void> unpairImage(int imageId) async {
    final db = await _database.database;
    final rows = await db.query(
      'tooth_images',
      columns: ['paired_image_id'],
      where: 'id = ?',
      whereArgs: [imageId],
    );
    if (rows.isEmpty) return;
    final partnerId = rows.first['paired_image_id'] as int?;
    await db.update(
      'tooth_images',
      const {'role': null, 'paired_image_id': null},
      where: 'id = ?',
      whereArgs: [imageId],
    );
    if (partnerId != null) {
      await db.update(
        'tooth_images',
        const {'role': null, 'paired_image_id': null},
        where: 'id = ?',
        whereArgs: [partnerId],
      );
    }
  }

  Future<void> updateImageAnnotations(int imageId, List<AnnotationShape> shapes) async {
    final db = await _database.database;
    await db.update(
      'tooth_images',
      {'annotations_json': encodeAnnotations(shapes)},
      where: 'id = ?',
      whereArgs: [imageId],
    );
  }

  Future<List<Appointment>> getAllAppointments() async {
    final db = await _database.database;
    final rows = await db.query('appointments', orderBy: 'date_time ASC');
    return rows.map(Appointment.fromMap).toList();
  }

  Future<List<Appointment>> getAppointmentsForPatient(int patientId) async {
    final db = await _database.database;
    final rows = await db.query(
      'appointments',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'date_time ASC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  Future<Appointment> addAppointment(Appointment appointment) async {
    final db = await _database.database;
    final id = await db.insert('appointments', appointment.toMap());
    return appointment.copyWith(id: id);
  }

  Future<void> updateAppointment(Appointment appointment) async {
    final db = await _database.database;
    await db.update(
      'appointments',
      appointment.toMap(),
      where: 'id = ?',
      whereArgs: [appointment.id],
    );
  }

  Future<void> deleteAppointment(int appointmentId) async {
    final db = await _database.database;
    await db.delete('appointments', where: 'id = ?', whereArgs: [appointmentId]);
  }

  /// Inserts a few sample patients with per-tooth notes on first run, so the
  /// chart has something to show out of the box. No-ops if any patient
  /// already exists.
  Future<void> seedSampleDataIfEmpty() async {
    final existing = await getPatients();
    if (existing.isNotEmpty) return;

    for (final seed in _sampleSeed) {
      final patient = await addPatient(seed.firstName, seed.lastName);
      await updatePatientMedicalInfo(
        patient.id!,
        allergies: seed.allergies,
        medications: seed.medications,
        medicalNotes: seed.medicalNotes,
      );
      for (final note in seed.notes) {
        await addNote(patient.id!, note.toothNumber, note.text, category: note.category);
      }
    }
  }
}

class _SeedNote {
  const _SeedNote(this.toothNumber, this.text, this.category);
  final int toothNumber;
  final String text;
  final NoteCategory category;
}

class _SeedPatient {
  const _SeedPatient(
    this.firstName,
    this.lastName,
    this.notes, {
    this.allergies = '',
    this.medications = '',
    this.medicalNotes = '',
  });
  final String firstName;
  final String lastName;
  final List<_SeedNote> notes;
  final String allergies;
  final String medications;
  final String medicalNotes;
}

const _sampleSeed = [
  _SeedPatient(
    'Anna',
    'Petrosyan',
    [
      _SeedNote(
        3,
        'Deep cavity on the occlusal surface, cleaned and filled with composite resin. No sensitivity reported at follow-up.',
        NoteCategory.filling,
      ),
      _SeedNote(
        14,
        'Root canal treatment completed over two visits. Crown placement recommended within the next month to protect the tooth.',
        NoteCategory.rootCanal,
      ),
      _SeedNote(
        30,
        'Early-stage decay spotted on routine check-up. Watching for progression; no treatment yet, re-evaluate in 6 months.',
        NoteCategory.consultation,
      ),
    ],
    allergies: 'Penicillin (rash)',
    medications: 'Metformin 500mg daily',
    medicalNotes: 'Type 2 diabetes, well controlled.',
  ),
  _SeedPatient(
    'David',
    'Grigoryan',
    [
      _SeedNote(
        8,
        'Chipped central incisor from a minor accident, repaired with composite bonding. Advised to avoid biting hard objects.',
        NoteCategory.filling,
      ),
      _SeedNote(
        19,
        'Large cavity between molars, filled after local anesthesia. Mild sensitivity to cold expected for 1-2 weeks.',
        NoteCategory.filling,
      ),
    ],
  ),
  _SeedPatient(
    'Mariam',
    'Sargsyan',
    [
      _SeedNote(
        2,
        'Severely decayed wisdom tooth extracted. Socket healing normally, follow-up scheduled in 2 weeks.',
        NoteCategory.extraction,
      ),
      _SeedNote(
        15,
        'Crown fitted after previous root canal therapy. Bite adjusted and polished; patient reports no discomfort.',
        NoteCategory.crown,
      ),
      _SeedNote(
        31,
        'Impacted wisdom tooth, mildly symptomatic. Extraction recommended, patient scheduling for next visit.',
        NoteCategory.consultation,
      ),
    ],
    allergies: 'Latex',
    medicalNotes: 'Pregnant (2nd trimester) - avoid X-rays unless essential.',
  ),
];
