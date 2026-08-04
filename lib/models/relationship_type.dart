enum RelationshipType {
  spouse('Spouse'),
  parent('Parent'),
  child('Child'),
  sibling('Sibling'),
  guardian('Guardian'),
  dependent('Dependent'),
  other('Other');

  const RelationshipType(this.label);

  final String label;

  /// The label the *other* patient's record should show for this same
  /// link, e.g. if A is B's Parent, B is A's Child.
  RelationshipType get reciprocal {
    switch (this) {
      case RelationshipType.spouse:
        return RelationshipType.spouse;
      case RelationshipType.parent:
        return RelationshipType.child;
      case RelationshipType.child:
        return RelationshipType.parent;
      case RelationshipType.sibling:
        return RelationshipType.sibling;
      case RelationshipType.guardian:
        return RelationshipType.dependent;
      case RelationshipType.dependent:
        return RelationshipType.guardian;
      case RelationshipType.other:
        return RelationshipType.other;
    }
  }

  static RelationshipType fromName(String? name) {
    return RelationshipType.values.firstWhere(
      (r) => r.name == name,
      orElse: () => RelationshipType.other,
    );
  }
}
