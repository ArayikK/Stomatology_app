import 'package:flutter/material.dart';

enum NoteCategory {
  consultation('Consultation', Color(0xFF5C6BC0)),
  filling('Filling', Color(0xFF26A69A)),
  rootCanal('Root Canal', Color(0xFFEF5350)),
  crown('Crown', Color(0xFFAB47BC)),
  extraction('Extraction', Color(0xFF8D6E63)),
  cleaning('Cleaning', Color(0xFF42A5F5)),
  xray('X-ray', Color(0xFF78909C)),
  other('Other', Color(0xFF9E9E9E));

  const NoteCategory(this.label, this.color);

  final String label;
  final Color color;

  static NoteCategory fromName(String? name) {
    return NoteCategory.values.firstWhere(
      (c) => c.name == name,
      orElse: () => NoteCategory.other,
    );
  }
}
