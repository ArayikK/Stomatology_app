import 'note_category.dart';

/// A prior version of a [ToothNote], captured automatically right before
/// each edit, so "what did this note used to say" is answerable and edits
/// are revertible.
class ToothNoteHistoryEntry {
  const ToothNoteHistoryEntry({
    this.id,
    required this.noteId,
    required this.text,
    required this.category,
    required this.editedAt,
  });

  final int? id;
  final int noteId;
  final String text;
  final NoteCategory category;
  final DateTime editedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'text': text,
      'category': category.name,
      'edited_at': editedAt.toIso8601String(),
    };
  }

  factory ToothNoteHistoryEntry.fromMap(Map<String, Object?> map) {
    return ToothNoteHistoryEntry(
      id: map['id'] as int?,
      noteId: map['note_id'] as int,
      text: map['text'] as String,
      category: NoteCategory.fromName(map['category'] as String?),
      editedAt: DateTime.parse(map['edited_at'] as String),
    );
  }
}
