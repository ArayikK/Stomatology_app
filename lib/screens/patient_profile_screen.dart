import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/note_category.dart';
import '../models/patient.dart';
import '../models/patient_relationship.dart';
import '../models/relationship_type.dart';
import '../models/tooth_note.dart';
import 'patient_chart_screen.dart';
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
            tabs: [
              Tab(text: 'Medical History'),
              Tab(text: 'Treatment Timeline'),
              Tab(text: 'Family'),
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
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _allergiesController = TextEditingController(text: widget.patient.allergies ?? '');
    _medicationsController = TextEditingController(text: widget.patient.medications ?? '');
    _notesController = TextEditingController(text: widget.patient.medicalNotes ?? '');
    for (final controller in [_allergiesController, _medicationsController, _notesController]) {
      controller.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
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
    setState(() {
      _saving = false;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medical history saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAllergies = _allergiesController.text.trim().isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: hasAllergies ? colorScheme.onErrorContainer : null,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _allergiesController,
                    maxLines: null,
                    style: hasAllergies
                        ? TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                    decoration: const InputDecoration(
                      hintText: 'None known - tap to add (e.g. penicillin, latex)',
                      border: InputBorder.none,
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
          const SizedBox(height: 24),
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
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(letterSpacing: 0.5, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: null,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
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
    _notesFuture = widget.repository.getAllNotesForPatient(widget.patient.id!);
  }

  void _reload() {
    setState(() {
      _notesFuture = widget.repository.getAllNotesForPatient(widget.patient.id!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ToothNote>>(
      future: _notesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final notes = snapshot.data ?? const [];
        if (notes.isEmpty) {
          return const Center(child: Text('No treatment history recorded yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
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
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ToothDetailScreen(
                        repository: widget.repository,
                        syncService: widget.syncService,
                        patientId: widget.patient.id!,
                        toothNumber: note.toothNumber,
                      ),
                    ),
                  );
                  _reload();
                },
                leading: CircleAvatar(
                  backgroundColor: note.category.color.withValues(alpha: 0.15),
                  child: Text(
                    '${note.toothNumber}',
                    style: TextStyle(color: note.category.color, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(note.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      _CategoryChip(category: note.category),
                      const SizedBox(width: 8),
                      Text(_formatDate(note.updatedAt), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
    final allPatients = await widget.repository.getPatients();
    final existing = await widget.repository.getRelationships(widget.patient.id!);
    final linkedIds = existing.map((r) => r.relatedPatient.id).toSet();
    final candidates = allPatients
        .where((p) => p.id != widget.patient.id && !linkedIds.contains(p.id))
        .toList();

    if (candidates.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No patients to link'),
          content: const Text(
            'Every other patient is already linked, or there are no other patients yet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final relatedPatient = await showDialog<Patient>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Link which patient?'),
        children: [
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(candidate),
              child: Text(candidate.fullName),
            ),
        ],
      ),
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
