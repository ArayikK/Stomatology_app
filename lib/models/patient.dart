class Patient {
  final int? id;
  final String firstName;
  final String lastName;
  final String? allergies;
  final String? medications;
  final String? medicalNotes;
  final DateTime createdAt;

  const Patient({
    this.id,
    required this.firstName,
    required this.lastName,
    this.allergies,
    this.medications,
    this.medicalNotes,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  bool get hasAllergies => (allergies ?? '').trim().isNotEmpty;

  Patient copyWith({
    int? id,
    String? allergies,
    String? medications,
    String? medicalNotes,
  }) {
    return Patient(
      id: id ?? this.id,
      firstName: firstName,
      lastName: lastName,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
      medicalNotes: medicalNotes ?? this.medicalNotes,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'allergies': allergies,
      'medications': medications,
      'medical_notes': medicalNotes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Patient.fromMap(Map<String, Object?> map) {
    return Patient(
      id: map['id'] as int?,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      allergies: map['allergies'] as String?,
      medications: map['medications'] as String?,
      medicalNotes: map['medical_notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
