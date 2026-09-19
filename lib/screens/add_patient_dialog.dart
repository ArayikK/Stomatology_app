import 'package:flutter/material.dart';

import '../data/dental_repository.dart';
import '../models/patient.dart';

/// Prompts for a first/last name and creates the patient. Returns the newly
/// created patient, or null if the dialog was cancelled. Shared by the home
/// screen's quick action, the patient list's "Add new" button and the
/// appointment patient picker.
///
/// [initialName] pre-fills the fields, so a name already typed into a search
/// box doesn't have to be typed again to add that person.
Future<Patient?> showAddPatientDialog(
  BuildContext context,
  DentalRepository repository, {
  String initialName = '',
}) async {
  final trimmed = initialName.trim();
  final splitAt = trimmed.indexOf(' ');
  final firstNameController = TextEditingController(
    text: splitAt == -1 ? trimmed : trimmed.substring(0, splitAt),
  );
  final lastNameController = TextEditingController(
    text: splitAt == -1 ? '' : trimmed.substring(splitAt + 1).trim(),
  );
  final formKey = GlobalKey<FormState>();

  final added = await showDialog<Patient>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Add patient'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: firstNameController,
                autofocus: firstNameController.text.isEmpty,
                decoration: const InputDecoration(labelText: 'First name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: lastNameController,
                autofocus: firstNameController.text.isNotEmpty,
                decoration: const InputDecoration(labelText: 'Last name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final patient = await repository.addPatient(
                firstNameController.text,
                lastNameController.text,
              );
              if (context.mounted) Navigator.of(context).pop(patient);
            },
            child: const Text('Add'),
          ),
        ],
      );
    },
  );

  firstNameController.dispose();
  lastNameController.dispose();

  return added;
}
