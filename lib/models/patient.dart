class Patient {
  final int? id;
  final String firstName;
  final String lastName;
  final DateTime createdAt;

  const Patient({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  Patient copyWith({int? id}) {
    return Patient(
      id: id ?? this.id,
      firstName: firstName,
      lastName: lastName,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Patient.fromMap(Map<String, Object?> map) {
    return Patient(
      id: map['id'] as int?,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
