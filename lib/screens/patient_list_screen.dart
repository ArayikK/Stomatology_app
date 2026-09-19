import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/patient.dart';
import '../models/patient_summary.dart';
import 'add_patient_dialog.dart';
import 'patient_chart_screen.dart';

/// Below this width, the chart opens as its own full-screen page; at or
/// above it, list and chart show side by side (tablet/stylus layout).
const double _wideLayoutBreakpoint = 840;

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
    final patient = await showAddPatientDialog(context, widget.repository);
    if (patient == null) return;
    _reload();
    unawaited(widget.syncService.pushAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
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
