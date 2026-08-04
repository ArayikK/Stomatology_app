import 'patient.dart';

/// A patient plus the list-screen-relevant facts that would otherwise need
/// a separate query per patient: whether they have any recorded treatment
/// history, and when they were last worked on.
class PatientSummary {
  const PatientSummary({
    required this.patient,
    required this.hasHistory,
    this.lastActivity,
  });

  final Patient patient;
  final bool hasHistory;
  final DateTime? lastActivity;
}
