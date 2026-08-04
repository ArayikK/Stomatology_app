import 'package:flutter/material.dart';

import '../data/dental_repository.dart';
import '../data/notification_service.dart';
import '../models/appointment.dart';
import '../models/patient.dart';

const List<int> _kDurations = [15, 30, 45, 60, 90, 120];
const Map<String, int?> _kReminderOptions = {
  'No reminder': null,
  '15 minutes before': 15,
  '30 minutes before': 30,
  '1 hour before': 60,
  '1 day before': 1440,
};

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, required this.repository});

  final DentalRepository repository;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsData {
  const _AppointmentsData({required this.appointments, required this.patientsById});
  final List<Appointment> appointments;
  final Map<int, Patient> patientsById;
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late Future<_AppointmentsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _dataFuture = _loadData();
  }

  Future<_AppointmentsData> _loadData() async {
    final appointments = await widget.repository.getAllAppointments();
    final patients = await widget.repository.getPatients();
    return _AppointmentsData(
      appointments: appointments,
      patientsById: {for (final p in patients) if (p.id != null) p.id!: p},
    );
  }

  Future<void> _openEditor({Appointment? existing, required List<Patient> patients}) async {
    if (patients.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No patients yet'),
          content: const Text('Add a patient first, then you can schedule their appointment.'),
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

    final result = await showDialog<_AppointmentFormResult>(
      context: context,
      builder: (context) => _AppointmentFormDialog(patients: patients, existing: existing),
    );
    if (result == null) return;

    if (existing == null) {
      final saved = await widget.repository.addAppointment(
        Appointment(
          patientId: result.patient.id!,
          dateTime: result.dateTime,
          durationMinutes: result.durationMinutes,
          notes: result.notes,
          reminderMinutesBefore: result.reminderMinutesBefore,
          createdAt: DateTime.now(),
        ),
      );
      await NotificationService.instance.scheduleReminder(saved, result.patient);
    } else {
      final updated = existing.copyWith(
        dateTime: result.dateTime,
        durationMinutes: result.durationMinutes,
        notes: result.notes,
        reminderMinutesBefore: result.reminderMinutesBefore,
        clearReminder: result.reminderMinutesBefore == null,
      );
      await widget.repository.updateAppointment(updated);
      await NotificationService.instance.cancelReminder(existing.id!);
      await NotificationService.instance.scheduleReminder(updated, result.patient);
    }
    setState(_load);
  }

  Future<void> _delete(Appointment appointment) async {
    await widget.repository.deleteAppointment(appointment.id!);
    await NotificationService.instance.cancelReminder(appointment.id!);
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appointments')),
      body: FutureBuilder<_AppointmentsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.appointments.isEmpty) {
            return const Center(child: Text('No appointments yet. Tap + to add one.'));
          }

          final groups = <DateTime, List<Appointment>>{};
          for (final appt in data.appointments) {
            final day = DateTime(appt.dateTime.year, appt.dateTime.month, appt.dateTime.day);
            groups.putIfAbsent(day, () => []).add(appt);
          }
          final sortedDays = groups.keys.toList()..sort();
          final now = DateTime.now();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final day in sortedDays) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_formatDay(day), style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final appt in groups[day]!)
                  Card(
                    child: ListTile(
                      enabled: appt.dateTime.isAfter(now),
                      leading: SizedBox(
                        width: 52,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_formatTimeOfDay(appt.dateTime), style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${appt.durationMinutes}m', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      title: Text(data.patientsById[appt.patientId]?.fullName ?? 'Unknown patient'),
                      subtitle: appt.notes.isEmpty ? null : Text(appt.notes, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (appt.reminderMinutesBefore != null)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.notifications_active_outlined, size: 18),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(appt),
                          ),
                        ],
                      ),
                      onTap: () => _openEditor(
                        existing: appt,
                        patients: data.patientsById.values.toList(),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final patients = await widget.repository.getPatients();
          if (!mounted) return;
          _openEditor(patients: patients);
        },
        icon: const Icon(Icons.add),
        label: const Text('New appointment'),
      ),
    );
  }
}

class _AppointmentFormResult {
  const _AppointmentFormResult({
    required this.patient,
    required this.dateTime,
    required this.durationMinutes,
    required this.notes,
    required this.reminderMinutesBefore,
  });

  final Patient patient;
  final DateTime dateTime;
  final int durationMinutes;
  final String notes;
  final int? reminderMinutesBefore;
}

class _AppointmentFormDialog extends StatefulWidget {
  const _AppointmentFormDialog({required this.patients, this.existing});

  final List<Patient> patients;
  final Appointment? existing;

  @override
  State<_AppointmentFormDialog> createState() => _AppointmentFormDialogState();
}

class _AppointmentFormDialogState extends State<_AppointmentFormDialog> {
  late Patient? _selectedPatient;
  late DateTime _date;
  late TimeOfDay _time;
  late int _duration;
  late final TextEditingController _notesController;
  int? _reminderMinutesBefore;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedPatient = existing == null
        ? (widget.patients.length == 1 ? widget.patients.first : null)
        : widget.patients.where((p) => p.id == existing.patientId).firstOrNull();
    final dt = existing?.dateTime ?? DateTime.now().add(const Duration(hours: 1));
    _date = DateTime(dt.year, dt.month, dt.day);
    _time = TimeOfDay(hour: dt.hour, minute: dt.minute);
    _duration = existing?.durationMinutes ?? 30;
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _reminderMinutesBefore = existing?.reminderMinutesBefore ?? 60;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  DateTime get _combinedDateTime =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New appointment' : 'Edit appointment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.existing == null)
              DropdownButtonFormField<Patient>(
                initialValue: _selectedPatient,
                decoration: const InputDecoration(labelText: 'Patient'),
                items: [
                  for (final patient in widget.patients)
                    DropdownMenuItem(value: patient, child: Text(patient.fullName)),
                ],
                onChanged: (value) => setState(() => _selectedPatient = value),
              )
            else
              Text('Patient: ${_selectedPatient?.fullName ?? 'Unknown'}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_formatDay(_date)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _duration,
              decoration: const InputDecoration(labelText: 'Duration'),
              items: [
                for (final minutes in _kDurations)
                  DropdownMenuItem(value: minutes, child: Text('$minutes minutes')),
              ],
              onChanged: (value) => setState(() => _duration = value ?? _duration),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _reminderMinutesBefore,
              decoration: const InputDecoration(labelText: 'Reminder'),
              items: [
                for (final entry in _kReminderOptions.entries)
                  DropdownMenuItem(value: entry.value, child: Text(entry.key)),
              ],
              onChanged: (value) => setState(() => _reminderMinutesBefore = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
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
          onPressed: _selectedPatient == null
              ? null
              : () => Navigator.of(context).pop(
                  _AppointmentFormResult(
                    patient: _selectedPatient!,
                    dateTime: _combinedDateTime,
                    durationMinutes: _duration,
                    notes: _notesController.text.trim(),
                    reminderMinutesBefore: _reminderMinutesBefore,
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? firstOrNull() {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

String _formatDay(DateTime day) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${weekdays[day.weekday - 1]}, ${day.year}-${two(day.month)}-${two(day.day)}';
}

String _formatTimeOfDay(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
