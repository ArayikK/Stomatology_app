import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/patient.dart';
import 'add_patient_dialog.dart';
import 'dialog_metrics.dart';

/// Picks a patient by searching for them, rather than by scrolling a list of
/// everyone in the practice - a plain dropdown stops being usable somewhere
/// around the second screenful, and a busy practice has thousands.
///
/// The picker can also create the patient on the spot: a first-time patient
/// being booked in is exactly when their record needs to exist. Anyone added
/// here is a normal patient record, so they show up in the patient list too.
///
/// Returns the chosen (or newly created) patient, or null if dismissed.
/// [excludeIds] leaves patients out of the results - the patient being linked
/// to themselves, say, or someone already linked.
Future<Patient?> showPatientPicker(
  BuildContext context, {
  required DentalRepository repository,
  BackendSyncService? syncService,
  String title = 'Choose patient',
  Set<int> excludeIds = const {},
}) {
  return showDialog<Patient>(
    context: context,
    builder: (context) => _PatientPickerDialog(
      repository: repository,
      syncService: syncService,
      title: title,
      excludeIds: excludeIds,
    ),
  );
}

class _PatientPickerDialog extends StatefulWidget {
  const _PatientPickerDialog({
    required this.repository,
    this.syncService,
    required this.title,
    required this.excludeIds,
  });

  final DentalRepository repository;
  final BackendSyncService? syncService;
  final String title;
  final Set<int> excludeIds;

  @override
  State<_PatientPickerDialog> createState() => _PatientPickerDialogState();
}

class _PatientPickerDialogState extends State<_PatientPickerDialog> {
  /// How many matches to show at once. Beyond this the answer is to type a
  /// couple more letters, not to scroll further.
  static const int _resultLimit = 50;

  final TextEditingController _searchController = TextEditingController();
  List<Patient> _results = const [];
  int _totalPatients = 0;
  bool _loading = true;

  /// Guards against an earlier, slower query overwriting the results of a
  /// later one when the dentist types quickly.
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _search('');
    _loadTotal();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTotal() async {
    final total = await widget.repository.countPatients();
    if (mounted) setState(() => _totalPatients = total);
  }

  Future<void> _search(String query) async {
    final token = ++_requestToken;
    setState(() => _loading = true);
    // Asks for the excluded ones on top of the limit, so filtering them out
    // can't leave the list short of a full page of real matches.
    final results = await widget.repository.searchPatients(
      query,
      limit: _resultLimit + widget.excludeIds.length,
    );
    if (!mounted || token != _requestToken) return;
    setState(() {
      _results = results
          .where((p) => !widget.excludeIds.contains(p.id))
          .take(_resultLimit)
          .toList();
      _loading = false;
    });
  }

  Future<void> _addNew() async {
    final created = await showAddPatientDialog(
      context,
      widget.repository,
      initialName: _searchController.text,
    );
    if (created == null) return;
    final syncService = widget.syncService;
    if (syncService != null) unawaited(syncService.pushAll());
    if (mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final query = _searchController.text.trim();

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: kDialogContentWidth(context),
        height: (screenHeight * 0.5).clamp(280.0, 440.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      ),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_add_alt_1,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                query.isEmpty ? 'Add a new patient' : 'Add "$query" as a new patient',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _addNew,
            ),
            const Divider(height: 1),
            Expanded(child: _buildResults(theme, query)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildResults(ThemeData theme, String query) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            query.isEmpty
                ? 'No patients yet. Add the first one above.'
                : 'No patient matches "$query".',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final capped = _results.length >= _resultLimit;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final patient = _results[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(
                    patient.firstName.isNotEmpty ? patient.firstName[0] : '?',
                  ),
                ),
                title: Text(patient.fullName, overflow: TextOverflow.ellipsis),
                subtitle: patient.hasAllergies
                    ? Text(
                        'Allergies: ${patient.allergies}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(patient),
              );
            },
          ),
        ),
        if (capped)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Showing first $_resultLimit of $_totalPatients - keep typing to narrow it down.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
