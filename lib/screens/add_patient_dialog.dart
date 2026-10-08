import 'package:flutter/material.dart';

import '../data/dental_repository.dart';
import '../models/patient.dart';

/// Prompts for a first/last name and creates the patient. Returns the newly
/// created patient, or null if the dialog was cancelled. Shared by the
/// patient list's "Add new" button and the appointment patient picker.
///
/// [initialName] pre-fills the fields, so a name already typed into a search
/// box doesn't have to be typed again to add that person.
Future<Patient?> showAddPatientDialog(
  BuildContext context,
  DentalRepository repository, {
  String initialName = '',
}) {
  return showDialog<Patient>(
    context: context,
    builder: (context) => _AddPatientDialog(
      repository: repository,
      initialName: initialName,
    ),
  );
}

/// A StatefulWidget rather than controllers created next to `showDialog`:
/// the dialog keeps rebuilding while it animates closed, so controllers
/// disposed the moment `showDialog` returns are still in use by the fields
/// and throw "used after being disposed". Owning them here ties their life
/// to the dialog's own.
class _AddPatientDialog extends StatefulWidget {
  const _AddPatientDialog({required this.repository, required this.initialName});

  final DentalRepository repository;
  final String initialName;

  @override
  State<_AddPatientDialog> createState() => _AddPatientDialogState();
}

class _AddPatientDialogState extends State<_AddPatientDialog> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final trimmed = widget.initialName.trim();
    final splitAt = trimmed.indexOf(' ');
    _firstName = TextEditingController(
      text: splitAt == -1 ? trimmed : trimmed.substring(0, splitAt),
    );
    _lastName = TextEditingController(
      text: splitAt == -1 ? '' : trimmed.substring(splitAt + 1).trim(),
    );
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true || _saving) return;
    setState(() => _saving = true);
    final patient = await widget.repository.addPatient(
      _firstName.text,
      _lastName.text,
    );
    if (mounted) Navigator.of(context).pop(patient);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add patient'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _firstName,
              autofocus: _firstName.text.isEmpty,
              decoration: const InputDecoration(labelText: 'First name'),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _lastName,
              autofocus: _firstName.text.isNotEmpty,
              decoration: const InputDecoration(labelText: 'Last name'),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
