import 'package:flutter/material.dart';

import '../chart/dental_chart.dart';
import '../chart/tooth_paths.dart';
import '../chart/tooth_state.dart';
import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/patient.dart';
import 'tooth_detail_sheet.dart';

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

  @override
  void initState() {
    super.initState();
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ToothDetailSheet(
        repository: widget.repository,
        syncService: widget.syncService,
        patientId: widget.patient.id!,
        toothNumber: toothNumber,
      ),
    );
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.patient.fullName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: kViewBoxWidth / kViewBoxHeight,
                  child: DentalChart(state: _toothStates, onToothTap: _onToothTap),
                ),
              ),
            ),
    );
  }
}
