import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/note_category.dart';
import '../models/patient.dart';
import '../models/patient_relationship.dart';
import '../models/relationship_type.dart';
import '../models/tooth_note.dart';
import 'dialog_metrics.dart';
import 'patient_chart_screen.dart';
import 'patient_picker.dart';
import 'tooth_detail_screen.dart';

/// Patient-level info that doesn't belong to any single tooth: medical
/// history/allergies, and a chronological feed of every note across every
/// tooth (the "treatment timeline").
class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({
    super.key,
    required this.repository,
    required this.syncService,
    required this.patient,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final Patient patient;

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  late Patient _patient;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_patient.fullName),
          bottom: const TabBar(
            // Tight label padding plus scale-down text keeps the longest
            // label ("Treatment Timeline") fully readable on narrow phones
            // instead of being clipped by its tab.
            labelPadding: EdgeInsets.symmetric(horizontal: 6),
            tabs: [
              _ProfileTab(label: 'Medical History'),
              _ProfileTab(label: 'Treatment Timeline'),
              _ProfileTab(label: 'Family'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MedicalHistoryTab(
              repository: widget.repository,
              patient: _patient,
              onSaved: (updated) => setState(() => _patient = updated),
            ),
            _TreatmentTimelineTab(
              repository: widget.repository,
              syncService: widget.syncService,
              patient: _patient,
            ),
            _FamilyTab(
              repository: widget.repository,
              syncService: widget.syncService,
              patient: _patient,
            ),
          ],
        ),
      ),
    );
  }
}

/// A tab whose label shrinks to fit its slice of the bar rather than
/// overflowing, so every tab title stays fully visible at any screen width.
class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, softWrap: false),
      ),
    );
  }
}

class _MedicalHistoryTab extends StatefulWidget {
  const _MedicalHistoryTab({
    required this.repository,
    required this.patient,
    required this.onSaved,
  });

  final DentalRepository repository;
  final Patient patient;
  final ValueChanged<Patient> onSaved;

  @override
  State<_MedicalHistoryTab> createState() => _MedicalHistoryTabState();
}

class _MedicalHistoryTabState extends State<_MedicalHistoryTab> {
  late final TextEditingController _allergiesController;
  late final TextEditingController _medicationsController;
  late final TextEditingController _notesController;
  bool _saving = false;

  /// Derived from the fields rather than latched by a flag, so it clears
  /// again if an edit is typed and then undone, and so the allergy banner
  /// and the Save button always agree with what's on screen.
  bool get _dirty =>
      _allergiesController.text.trim() != (widget.patient.allergies ?? '').trim() ||
      _medicationsController.text.trim() != (widget.patient.medications ?? '').trim() ||
      _notesController.text.trim() != (widget.patient.medicalNotes ?? '').trim();

  @override
  void initState() {
    super.initState();
    _allergiesController = TextEditingController(text: widget.patient.allergies ?? '');
    _medicationsController = TextEditingController(text: widget.patient.medications ?? '');
    _notesController = TextEditingController(text: widget.patient.medicalNotes ?? '');
    for (final controller in [_allergiesController, _medicationsController, _notesController]) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _allergiesController.dispose();
    _medicationsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.repository.updatePatientMedicalInfo(
      widget.patient.id!,
      allergies: _allergiesController.text,
      medications: _medicationsController.text,
      medicalNotes: _notesController.text,
    );
    widget.onSaved(
      widget.patient.copyWith(
        allergies: _allergiesController.text.trim(),
        medications: _medicationsController.text.trim(),
        medicalNotes: _notesController.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medical history saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAllergies = _allergiesController.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Card(
            color: hasAllergies ? colorScheme.errorContainer : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: hasAllergies ? colorScheme.error : colorScheme.outlineVariant,
                width: hasAllergies ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: hasAllergies ? colorScheme.onErrorContainer : colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ALLERGIES',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: hasAllergies ? colorScheme.onErrorContainer : null,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // A bordered field, not borderless text: the whole tab used
                  // to read as a printed record rather than as something you
                  // can type into.
                  TextField(
                    controller: _allergiesController,
                    maxLines: null,
                    style: hasAllergies
                        ? TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                    decoration: InputDecoration(
                      hintText: 'None known - type to add (e.g. penicillin, latex)',
                      border: const OutlineInputBorder(),
                      filled: hasAllergies,
                      fillColor: hasAllergies ? colorScheme.surface : null,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _MedicalField(
            label: 'Current medications',
            controller: _medicationsController,
            hint: 'e.g. blood thinners, medications affecting treatment',
          ),
          const SizedBox(height: 16),
          _MedicalField(
            label: 'Medical history / conditions',
            controller: _notesController,
            hint: 'e.g. diabetes, pregnancy, heart conditions, past surgeries',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_dirty && !_saving) ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save changes'),
          ),
          const SizedBox(height: 8),
          Text(
            _dirty ? 'Unsaved changes' : 'Everything here is saved.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _dirty ? colorScheme.error : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicalField extends StatelessWidget {
  const _MedicalField({required this.label, required this.controller, required this.hint});

  final String label;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 0.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: null,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreatmentTimelineTab extends StatefulWidget {
  const _TreatmentTimelineTab({
    required this.repository,
    required this.syncService,
    required this.patient,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final Patient patient;

  @override
  State<_TreatmentTimelineTab> createState() => _TreatmentTimelineTabState();
}

class _TreatmentTimelineTabState extends State<_TreatmentTimelineTab> {
  late Future<List<ToothNote>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _notesFuture = widget.repository.getAllNotesForPatient(widget.patient.id!);
  }

  void _reload() => setState(_load);

  /// Records a treatment straight onto the timeline. The same entries also
  /// show on the tooth they belong to, so this is a second way into the
  /// same records rather than a separate list - and an entry that isn't
  /// about one tooth (a cleaning, a check-up) can go in as "general".
  Future<void> _addEntry() async {
    final result = await showDialog<_TimelineEntryResult>(
      context: context,
      builder: (context) => const _TimelineEntryDialog(),
    );
    if (result == null) return;

    await widget.repository.addNote(
      widget.patient.id!,
      result.toothNumber,
      result.text,
      category: result.category,
      createdAt: result.date,
    );
    if (!mounted) return;
    _reload();
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _editEntry(ToothNote note) async {
    final result = await showDialog<_TimelineEntryResult>(
      context: context,
      builder: (context) => _TimelineEntryDialog(existing: note),
    );
    if (result == null) return;

    await widget.repository.updateNote(
      note,
      result.text,
      category: result.category,
      createdAt: result.date,
    );
    if (result.toothNumber != note.toothNumber) {
      await widget.repository.moveNoteToTooth(note.id!, result.toothNumber);
    }
    if (!mounted) return;
    _reload();
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _deleteEntry(ToothNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(note.text, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.repository.deleteNote(note.id!);
    if (!mounted) return;
    _reload();
    unawaited(widget.syncService.pushAll());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Entry deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.repository.addNote(
              note.patientId,
              note.toothNumber,
              note.text,
              category: note.category,
              createdAt: note.createdAt,
            );
            if (mounted) _reload();
            unawaited(widget.syncService.pushAll());
          },
        ),
      ),
    );
  }

  Future<void> _openTooth(int toothNumber) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ToothDetailScreen(
          repository: widget.repository,
          syncService: widget.syncService,
          patientId: widget.patient.id!,
          toothNumber: toothNumber,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<ToothNote>>(
        future: _notesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data ?? const [];
          if (notes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No treatment history recorded yet.\n'
                  'Tap "Add entry" to record a visit, or add notes from a tooth on the chart.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: notes.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: note.category.color.withValues(alpha: 0.4)),
                ),
                child: ListTile(
                  onTap: () =>
                      note.isGeneral ? _editEntry(note) : _openTooth(note.toothNumber),
                  leading: CircleAvatar(
                    backgroundColor: note.category.color.withValues(alpha: 0.15),
                    child: note.isGeneral
                        ? Icon(
                            Icons.medical_services_outlined,
                            size: 18,
                            color: note.category.color,
                          )
                        : Text(
                            '${note.toothNumber}',
                            style: TextStyle(
                              color: note.category.color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  title: Text(note.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _CategoryChip(category: note.category),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatDate(note.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Entry options',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editEntry(note);
                        case 'tooth':
                          _openTooth(note.toothNumber);
                        case 'delete':
                          _deleteEntry(note);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit entry')),
                      if (!note.isGeneral)
                        PopupMenuItem(
                          value: 'tooth',
                          child: Text('Open tooth ${note.toothNumber}'),
                        ),
                      const PopupMenuItem(value: 'delete', child: Text('Delete entry')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEntry,
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
    );
  }
}

class _TimelineEntryResult {
  const _TimelineEntryResult({
    required this.toothNumber,
    required this.category,
    required this.text,
    required this.date,
  });

  final int toothNumber;
  final NoteCategory category;
  final String text;
  final DateTime date;
}

/// Add/edit form for one timeline entry. The date is editable because
/// treatment often gets written up after the fact, and a timeline that
/// always says "today" is no timeline at all.
class _TimelineEntryDialog extends StatefulWidget {
  const _TimelineEntryDialog({this.existing});

  final ToothNote? existing;

  @override
  State<_TimelineEntryDialog> createState() => _TimelineEntryDialogState();
}

class _TimelineEntryDialogState extends State<_TimelineEntryDialog> {
  late int _toothNumber;
  late NoteCategory _category;
  late DateTime _date;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _toothNumber = existing?.toothNumber ?? kGeneralToothNumber;
    _category = existing?.category ?? NoteCategory.consultation;
    _date = existing?.createdAt ?? DateTime.now();
    _textController = TextEditingController(text: existing?.text ?? '');
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day, 12));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = kDialogContentWidth(context);
    const chipSpacing = 8.0;
    final chipColumns = dialogWidth >= 380 ? 3 : 2;
    final chipWidth = (dialogWidth - chipSpacing * (chipColumns - 1)) / chipColumns;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add timeline entry' : 'Edit entry'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _toothNumber,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Applies to',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: kGeneralToothNumber,
                    child: Text('General (no specific tooth)'),
                  ),
                  for (var number = 1; number <= 32; number++)
                    DropdownMenuItem(value: number, child: Text('Tooth $number')),
                ],
                onChanged: (value) =>
                    setState(() => _toothNumber = value ?? _toothNumber),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('Date: ${_formatDate(_date)}'),
                ),
              ),
              const SizedBox(height: 16),
              Text('Category', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: chipSpacing,
                runSpacing: chipSpacing,
                children: [
                  for (final category in NoteCategory.values)
                    SizedBox(
                      width: chipWidth,
                      child: ChoiceChip(
                        label: Center(
                          child: Text(
                            category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        selected: _category == category,
                        showCheckmark: false,
                        selectedColor: category.color.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: category.color.withValues(
                            alpha: _category == category ? 0.9 : 0.4,
                          ),
                        ),
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _textController,
                autofocus: widget.existing == null,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'What was done',
                  hintText: 'Describe the treatment, findings or advice given...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _textController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _TimelineEntryResult(
                    toothNumber: _toothNumber,
                    category: _category,
                    text: _textController.text.trim(),
                    date: _date,
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final NoteCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        category.label,
        style: TextStyle(color: category.color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FamilyTab extends StatefulWidget {
  const _FamilyTab({
    required this.repository,
    required this.syncService,
    required this.patient,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final Patient patient;

  @override
  State<_FamilyTab> createState() => _FamilyTabState();
}

class _FamilyTabState extends State<_FamilyTab> {
  late Future<List<PatientRelationship>> _relationshipsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _relationshipsFuture = widget.repository.getRelationships(widget.patient.id!);
  }

  Future<void> _addRelationship() async {
    final existing = await widget.repository.getRelationships(widget.patient.id!);
    if (!mounted) return;

    // Searched rather than listed, and able to create the relative on the
    // spot - the family member being linked is often a new patient too.
    final relatedPatient = await showPatientPicker(
      context,
      repository: widget.repository,
      syncService: widget.syncService,
      title: 'Link which patient?',
      excludeIds: {
        widget.patient.id!,
        for (final relationship in existing)
          if (relationship.relatedPatient.id != null) relationship.relatedPatient.id!,
      },
    );
    if (relatedPatient == null || !mounted) return;

    final type = await showDialog<RelationshipType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('How is ${widget.patient.firstName} related to ${relatedPatient.firstName}?'),
        children: [
          for (final option in RelationshipType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option),
              child: Text(option.label),
            ),
        ],
      ),
    );
    if (type == null) return;

    await widget.repository.linkPatients(widget.patient.id!, relatedPatient.id!, type);
    setState(_load);
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _unlink(PatientRelationship relationship) async {
    await widget.repository.unlinkPatients(widget.patient.id!, relationship.relatedPatient.id!);
    setState(_load);
    unawaited(widget.syncService.pushAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<PatientRelationship>>(
        future: _relationshipsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final relationships = snapshot.data ?? const [];
          if (relationships.isEmpty) {
            return const Center(child: Text('No family/relationship links yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: relationships.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final relationship = relationships[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    relationship.relatedPatient.firstName.isNotEmpty
                        ? relationship.relatedPatient.firstName[0]
                        : '?',
                  ),
                ),
                title: Text(relationship.relatedPatient.fullName),
                subtitle: Text(relationship.type.label),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off),
                  tooltip: 'Unlink',
                  onPressed: () => _unlink(relationship),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PatientChartScreen(
                        repository: widget.repository,
                        syncService: widget.syncService,
                        patient: relationship.relatedPatient,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRelationship,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Link patient'),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
