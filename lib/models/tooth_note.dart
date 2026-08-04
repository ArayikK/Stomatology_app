import 'note_category.dart';

class ToothNote {
  final int? id;
  final int patientId;
  final int toothNumber;
  final String text;
  final NoteCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ToothNote({
    this.id,
    required this.patientId,
    required this.toothNumber,
    required this.text,
    this.category = NoteCategory.other,
    required this.createdAt,
    required this.updatedAt,
  });

  ToothNote copyWith({
    int? id,
    String? text,
    NoteCategory? category,
    DateTime? updatedAt,
  }) {
    return ToothNote(
      id: id ?? this.id,
      patientId: patientId,
      toothNumber: toothNumber,
      text: text ?? this.text,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'tooth_number': toothNumber,
      'text': text,
      'category': category.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ToothNote.fromMap(Map<String, Object?> map) {
    return ToothNote(
      id: map['id'] as int?,
      patientId: map['patient_id'] as int,
      toothNumber: map['tooth_number'] as int,
      text: map['text'] as String,
      category: NoteCategory.fromName(map['category'] as String?),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
