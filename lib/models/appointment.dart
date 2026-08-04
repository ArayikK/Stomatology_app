class Appointment {
  final int? id;
  final int patientId;
  final DateTime dateTime;
  final int durationMinutes;
  final String notes;

  /// Null means no reminder notification.
  final int? reminderMinutesBefore;
  final DateTime createdAt;

  const Appointment({
    this.id,
    required this.patientId,
    required this.dateTime,
    this.durationMinutes = 30,
    this.notes = '',
    this.reminderMinutesBefore,
    required this.createdAt,
  });

  Appointment copyWith({
    int? id,
    DateTime? dateTime,
    int? durationMinutes,
    String? notes,
    int? reminderMinutesBefore,
    bool clearReminder = false,
  }) {
    return Appointment(
      id: id ?? this.id,
      patientId: patientId,
      dateTime: dateTime ?? this.dateTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      notes: notes ?? this.notes,
      reminderMinutesBefore:
          clearReminder ? null : (reminderMinutesBefore ?? this.reminderMinutesBefore),
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'date_time': dateTime.toIso8601String(),
      'duration_minutes': durationMinutes,
      'notes': notes,
      'reminder_minutes_before': reminderMinutesBefore,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Appointment.fromMap(Map<String, Object?> map) {
    return Appointment(
      id: map['id'] as int?,
      patientId: map['patient_id'] as int,
      dateTime: DateTime.parse(map['date_time'] as String),
      durationMinutes: map['duration_minutes'] as int? ?? 30,
      notes: map['notes'] as String? ?? '',
      reminderMinutesBefore: map['reminder_minutes_before'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
