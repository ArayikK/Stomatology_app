import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../data/device_identity.dart';
import '../legal/legal_content.dart';
import '../models/patient.dart';
import 'faq_screen.dart';
import 'legal_document_screen.dart';
import 'patient_chart_screen.dart';

enum _MenuAction { syncNow, restoreFromCloud, deviceId, privacy, terms, faq }

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
  late Future<List<Patient>> _patientsFuture;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _patientsFuture = widget.repository.getPatients();
  }

  void _reload() {
    setState(() {
      _patientsFuture = widget.repository.getPatients();
    });
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
      body: FutureBuilder<List<Patient>>(
        future: _patientsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final patients = snapshot.data ?? const [];
          if (patients.isEmpty) {
            return const Center(child: Text('No patients yet. Tap + to add one.'));
          }
          return ListView.separated(
            itemCount: patients.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final patient = patients[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    patient.firstName.isNotEmpty ? patient.firstName[0] : '?',
                  ),
                ),
                title: Text(patient.fullName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PatientChartScreen(
                        repository: widget.repository,
                        syncService: widget.syncService,
                        patient: patient,
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
        onPressed: _openAddPatientDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add new'),
      ),
    );
  }
}
