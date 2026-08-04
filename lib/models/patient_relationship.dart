import 'patient.dart';
import 'relationship_type.dart';

/// A link from one patient to another (e.g. "this patient's Spouse is
/// that patient"), from the owning patient's point of view.
class PatientRelationship {
  const PatientRelationship({
    required this.relatedPatient,
    required this.type,
  });

  final Patient relatedPatient;
  final RelationshipType type;
}
