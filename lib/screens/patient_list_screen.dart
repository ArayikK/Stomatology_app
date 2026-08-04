import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../data/device_identity.dart';
import '../legal/legal_content.dart';
import '../models/patient.dart';
import '../models/patient_summary.dart';
import 'appointments_screen.dart';
import 'faq_screen.dart';
import 'legal_document_screen.dart';
import 'patient_chart_screen.dart';

/// Below this width, the chart opens as its own full-screen page; at or
/// above it, list and chart show side by side (tablet/stylus layout).
const double _wideLayoutBreakpoint = 840;

enum _MenuAction { syncNow, restoreFromCloud, deviceId, privacy, terms, faq }

enum _SortOrder { name, recentActivity }

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({
    super.key,
    required this.repository,
    required this.syncService,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  late Future<List<PatientSummary>> _summariesFuture;
  bool _syncing = false;
  String _searchQuery = '';
  bool _onlyWithHistory = false;
  _SortOrder _sortOrder = _SortOrder.name;
  Patient? _selectedPatient;

  @override
  void initState() {
    super.initState();
    _summariesFuture = widget.repository.getPatientSummaries();
  }

  void _reload() {
    setState(() {
      _summariesFuture = widget.repository.getPatientSummaries();
    });
  }

  List<PatientSummary> _applyFilters(List<PatientSummary> summaries) {
    final query = _searchQuery.trim().toLowerCase();
    var filtered = summaries.where((s) {
      if (_onlyWithHistory && !s.hasHistory) return false;
      if (query.isEmpty) return true;
      return s.patient.fullName.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      if (_sortOrder == _SortOrder.recentActivity) {
        final aTime = a.lastActivity;
        final bTime = b.lastActivity;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      }
      return a.patient.fullName.toLowerCase().compareTo(b.patient.fullName.toLowerCase());
    });
    return filtered;
  }

  Future<void> _openAddPatientDialog() async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final added = await showDialog<bool>(
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
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'First name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: lastNameController,
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                await widget.repository.addPatient(
                  firstNameController.text,
                  lastNameController.text,
                );
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    firstNameController.dispose();
    lastNameController.dispose();

    if (added == true) {
      _reload();
      unawaited(widget.syncService.pushAll());
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final ok = await widget.syncService.pushAll();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Synced to cloud backup.' : 'Could not reach the backend.'),
      ),
    );
  }

  Future<void> _restoreFromCloud() async {
    final currentPatients = await widget.repository.getPatients();
    if (!mounted) return;
    if (currentPatients.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Restore is only available when the patient list is empty, to avoid duplicating data.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from cloud backup?'),
        content: const Text(
          'This will fetch this device\'s most recent cloud backup, if one exists, '
          'and recreate its patients, notes, and images locally.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _syncing = true);
    final payload = await widget.syncService.pullAll();
    if (payload == null) {
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cloud backup found for this device.')),
      );
      return;
    }
    final restoredCount = await widget.syncService.restoreFromPayload(payload);
    if (!mounted) return;
    setState(() => _syncing = false);
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored $restoredCount patient(s) from cloud backup.')),
    );
  }

  Future<void> _showDeviceId() async {
    final id = await DeviceIdentity.get();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This device\'s identifier'),
        content: SelectableText(id),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(_MenuAction action) {
    switch (action) {
      case _MenuAction.syncNow:
        _syncNow();
      case _MenuAction.restoreFromCloud:
        _restoreFromCloud();
      case _MenuAction.deviceId:
        _showDeviceId();
      case _MenuAction.privacy:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const LegalDocumentScreen(
              title: 'Privacy Policy',
              sections: kPrivacyPolicySections,
            ),
          ),
        );
      case _MenuAction.terms:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const LegalDocumentScreen(
              title: 'Terms & Conditions',
              sections: kTermsSections,
            ),
          ),
        );
      case _MenuAction.faq:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const FaqScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          IconButton(
            tooltip: 'Appointments',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AppointmentsScreen(repository: widget.repository),
                ),
              );
            },
          ),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          PopupMenuButton<_MenuAction>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _MenuAction.syncNow, child: Text('Sync now')),
              PopupMenuItem(
                value: _MenuAction.restoreFromCloud,
                child: Text('Restore from cloud backup'),
              ),
              PopupMenuItem(value: _MenuAction.deviceId, child: Text('Device identifier')),
              PopupMenuDivider(),
              PopupMenuItem(value: _MenuAction.privacy, child: Text('Privacy Policy')),
              PopupMenuItem(value: _MenuAction.terms, child: Text('Terms & Conditions')),
              PopupMenuItem(value: _MenuAction.faq, child: Text('FAQ')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideLayoutBreakpoint;
          final listColumn = _buildListColumn(context, wide: isWide);
          if (!isWide) return listColumn;

          return Row(
            children: [
              SizedBox(width: 380, child: listColumn),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selectedPatient == null
                    ? const Center(child: Text('Select a patient to view their chart.'))
                    : PatientChartScreen(
                        key: ValueKey(_selectedPatient!.id),
                        repository: widget.repository,
                        syncService: widget.syncService,
                        patient: _selectedPatient!,
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddPatientDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add new'),
      ),
    );
  }

  Widget _buildListColumn(BuildContext context, {required bool wide}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search patients by name...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Has treatment history'),
                selected: _onlyWithHistory,
                onSelected: (value) => setState(() => _onlyWithHistory = value),
              ),
              const Spacer(),
              PopupMenuButton<_SortOrder>(
                tooltip: 'Sort',
                initialValue: _sortOrder,
                onSelected: (value) => setState(() => _sortOrder = value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _SortOrder.name, child: Text('Sort: Name')),
                  PopupMenuItem(
                    value: _SortOrder.recentActivity,
                    child: Text('Sort: Last visit'),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort),
                    const SizedBox(width: 4),
                    Text(
                      _sortOrder == _SortOrder.name ? 'Name' : 'Last visit',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: FutureBuilder<List<PatientSummary>>(
            future: _summariesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data ?? const [];
              if (all.isEmpty) {
                return const Center(child: Text('No patients yet. Tap + to add one.'));
              }
              final summaries = _applyFilters(all);
              if (summaries.isEmpty) {
                return const Center(child: Text('No patients match your search/filter.'));
              }
              return ListView.separated(
                itemCount: summaries.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final summary = summaries[index];
                  final patient = summary.patient;
                  return ListTile(
                    selected: wide && _selectedPatient?.id == patient.id,
                    leading: CircleAvatar(
                      child: Text(
                        patient.firstName.isNotEmpty ? patient.firstName[0] : '?',
                      ),
                    ),
                    title: Text(patient.fullName),
                    subtitle: Text(
                      summary.lastActivity == null
                          ? 'No visits recorded'
                          : 'Last visit: ${_formatDate(summary.lastActivity!)}',
                    ),
                    trailing: wide ? null : const Icon(Icons.chevron_right),
                    onTap: () async {
                      if (wide) {
                        setState(() {
                          _selectedPatient = patient;
                          _summariesFuture = widget.repository.getPatientSummaries();
                        });
                        return;
                      }
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => PatientChartScreen(
                            repository: widget.repository,
                            syncService: widget.syncService,
                            patient: patient,
                          ),
                        ),
                      );
                      _reload();
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
