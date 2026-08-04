import 'package:flutter/material.dart';

import '../chart/dental_chart.dart';
import '../chart/tooth_paths.dart';
import '../chart/tooth_state.dart';
import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/patient.dart';
import 'patient_profile_screen.dart';
import 'tooth_detail_screen.dart';

class PatientChartScreen extends StatefulWidget {
  const PatientChartScreen({
    super.key,
    required this.repository,
    required this.syncService,
    required this.patient,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final Patient patient;

  @override
  State<PatientChartScreen> createState() => _PatientChartScreenState();
}

class _PatientChartScreenState extends State<PatientChartScreen> {
  Map<int, ToothState> _toothStates = const {};
  bool _loading = true;
  late Patient _patient;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final withHistory = await widget.repository.getTeethWithHistory(
      widget.patient.id!,
    );
    if (!mounted) return;
    setState(() {
      _toothStates = {
        for (var number = 1; number <= 32; number++)
          number: ToothState(number: number, hasHistory: withHistory.contains(number)),
      };
      _loading = false;
    });
  }

  Future<void> _onToothTap(int toothNumber) async {
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
    await _loadHistory();
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PatientProfileScreen(
          repository: widget.repository,
          syncService: widget.syncService,
          patient: _patient,
        ),
      ),
    );
    final patients = await widget.repository.getPatients();
    final refreshed = patients.where((p) => p.id == _patient.id).toList();
    if (mounted && refreshed.isNotEmpty) {
      setState(() => _patient = refreshed.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_patient.fullName),
        actions: [
          IconButton(
            tooltip: 'Medical history & treatment timeline',
            icon: const Icon(Icons.folder_shared_outlined),
            onPressed: _openProfile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_patient.hasAllergies)
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: InkWell(
                      onTap: _openProfile,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Theme.of(context).colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Allergies: ${_patient.allergies}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AspectRatio(
                        aspectRatio: kViewBoxWidth / kViewBoxHeight,
                        child: DentalChart(state: _toothStates, onToothTap: _onToothTap),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
