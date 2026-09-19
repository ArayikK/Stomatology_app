import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../data/notification_service.dart';
import '../models/appointment.dart';
import '../models/patient.dart';
import 'dialog_metrics.dart';
import 'patient_chart_screen.dart';
import 'patient_picker.dart';
import '../tour/app_tour.dart';
import '../tour/spotlight_tour.dart';

const List<int> _kDurations = [15, 30, 45, 60, 90, 120];
const Map<String, int?> _kReminderOptions = {
  'No reminder': null,
  '15 minutes before': 15,
  '30 minutes before': 30,
  '1 hour before': 60,
  '1 day before': 1440,
};

/// One-tap times for the slots a practice actually books, so the time picker
/// is only needed for the odd one out.
const List<TimeOfDay> _kQuickTimes = [
  TimeOfDay(hour: 9, minute: 0),
  TimeOfDay(hour: 9, minute: 30),
  TimeOfDay(hour: 10, minute: 0),
  TimeOfDay(hour: 11, minute: 0),
  TimeOfDay(hour: 12, minute: 0),
  TimeOfDay(hour: 14, minute: 0),
  TimeOfDay(hour: 15, minute: 0),
  TimeOfDay(hour: 16, minute: 0),
  TimeOfDay(hour: 17, minute: 0),
];

/// Follow-up intervals offered when repeating an appointment.
const Map<String, int> _kFollowUpDays = {
  'In 1 week': 7,
  'In 2 weeks': 14,
  'In 1 month': 30,
  'In 3 months': 90,
  'In 6 months': 180,
};

/// Which of the two calendar views the screen opens on.
enum AppointmentsView { agenda, month }

enum _AgendaFilter { upcoming, all, past }

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.repository,
    required this.syncService,
    this.initialView = AppointmentsView.agenda,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final AppointmentsView initialView;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsData {
  const _AppointmentsData({required this.appointments, required this.patientsById});
  final List<Appointment> appointments;
  final Map<int, Patient> patientsById;

  List<Appointment> onDay(DateTime day) {
    return appointments.where((a) => _isSameDay(a.dateTime, day)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late Future<_AppointmentsData> _dataFuture;
  late AppointmentsView _viewMode;
  _AgendaFilter _filter = _AgendaFilter.upcoming;
  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  /// Sits on the agenda's first day heading from today onwards, so "Today"
  /// has something to scroll to.
  final GlobalKey _agendaTodayKey = GlobalKey();

  final GlobalKey _viewToggleKey = GlobalKey();
  final GlobalKey _todayButtonKey = GlobalKey();
  final GlobalKey _newAppointmentKey = GlobalKey();

  List<TourStep> get _tourSteps => [
    TourStep(
      target: _viewToggleKey,
      title: 'Agenda or month',
      body: 'Agenda lists visits day by day. Month shows a calendar, where you tap a day to see its visits.',
    ),
    TourStep(
      target: _todayButtonKey,
      title: 'Back to today',
      body: 'Jumps straight to today, however far you have scrolled.',
      pad: 4,
    ),
    TourStep(
      target: _newAppointmentKey,
      title: 'Book a visit',
      body: 'Pick a patient, a time and a length. Add a reminder and your phone will notify you before the visit.',
      pad: 6,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _viewMode = widget.initialView;
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _load();
    _dataFuture.then((_) {
      if (mounted) AppTour.maybeShow(context, TourScreen.appointments, _tourSteps);
    }, onError: (_) {});
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

  void _reload() => setState(_load);

  /// "Today" has to mean something in both views: in the month grid it moves
  /// the focus and selection, and in the agenda it scrolls to today's
  /// heading. When there is nothing to scroll to it says so, rather than
  /// looking like a dead button.
  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
      if (_filter == _AgendaFilter.past) _filter = _AgendaFilter.upcoming;
    });
    if (_viewMode != AppointmentsView.agenda) return;

    // After the setState above has rebuilt the list, so the anchor key is
    // attached to whichever heading is now the first one from today onwards.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _agendaTodayKey.currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(
          anchor,
          alignment: 0.05,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing booked from today onwards. Tap + to schedule a visit.'),
        ),
      );
    });
  }

  // ---------------------------------------------------------------- editing

  Future<void> _openEditor({
    Appointment? existing,
    Patient? existingPatient,
    DateTime? initialDay,
  }) async {
    // No "add a patient first" gate: the form's patient picker can create one,
    // which is what a call from a first-time patient actually needs.
    final result = await showDialog<_AppointmentFormResult>(
      context: context,
      builder: (context) => _AppointmentFormDialog(
        repository: widget.repository,
        syncService: widget.syncService,
        existing: existing,
        existingPatient: existingPatient,
        initialDay: initialDay,
      ),
    );
    if (result == null) return;

    final allowed = await _confirmNoClash(
      dateTime: result.dateTime,
      durationMinutes: result.durationMinutes,
      ignoreAppointmentId: existing?.id,
    );
    if (!allowed) return;

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
    if (!mounted) return;
    setState(() {
      _selectedDay = DateTime(
        result.dateTime.year,
        result.dateTime.month,
        result.dateTime.day,
      );
      _focusedMonth = DateTime(result.dateTime.year, result.dateTime.month);
      _load();
    });
  }

  /// Warns when the requested slot overlaps an appointment that is already
  /// booked. Double-booking stays possible (two chairs, an overrun), it just
  /// shouldn't happen by accident. Returns whether to go ahead.
  Future<bool> _confirmNoClash({
    required DateTime dateTime,
    required int durationMinutes,
    int? ignoreAppointmentId,
  }) async {
    final data = await _dataFuture;
    final end = dateTime.add(Duration(minutes: durationMinutes));
    Appointment? clash;
    for (final other in data.appointments) {
      if (other.id == ignoreAppointmentId) continue;
      final otherEnd = other.dateTime.add(Duration(minutes: other.durationMinutes));
      if (dateTime.isBefore(otherEnd) && other.dateTime.isBefore(end)) {
        clash = other;
        break;
      }
    }
    if (clash == null || !mounted) return true;

    final name = data.patientsById[clash.patientId]?.fullName ?? 'another patient';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.event_busy_outlined),
        title: const Text('That slot is taken'),
        content: Text(
          '$name is already booked ${_formatTimeOfDay(clash!.dateTime)}-'
          '${_formatTimeOfDay(clash.dateTime.add(Duration(minutes: clash.durationMinutes)))} '
          'on ${_formatDay(clash.dateTime)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Pick another time'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Book anyway'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ---------------------------------------------------- per-appointment ops

  /// The options sheet for one appointment: everything you might want to do
  /// with a booking without hunting through the edit form.
  Future<void> _openOptions(Appointment appointment, _AppointmentsData data) async {
    final patient = data.patientsById[appointment.patientId];
    final end = appointment.dateTime.add(Duration(minutes: appointment.durationMinutes));

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient?.fullName ?? 'Unknown patient',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDay(appointment.dateTime)} - '
                      '${_formatTimeOfDay(appointment.dateTime)}-${_formatTimeOfDay(end)}',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit details'),
                onTap: () {
                  close();
                  _openEditor(existing: appointment, existingPatient: patient);
                },
              ),
              ListTile(
                leading: const Icon(Icons.update_outlined),
                title: const Text('Reschedule'),
                subtitle: const Text('Move by a day or a week, or pick a new date'),
                onTap: () {
                  close();
                  _openReschedule(appointment, patient);
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text('Book follow-up'),
                subtitle: const Text('Same patient, same time, later date'),
                onTap: () {
                  close();
                  _openFollowUp(appointment, patient);
                },
              ),
              if (patient != null)
                ListTile(
                  leading: const Icon(Icons.medical_services_outlined),
                  title: const Text('Open patient chart'),
                  onTap: () {
                    close();
                    _openChart(patient);
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Cancel appointment',
                  style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                ),
                onTap: () {
                  close();
                  _delete(appointment, patient);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openReschedule(Appointment appointment, Patient? patient) async {
    final choice = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final options = <String, DateTime>{
          'Tomorrow, same time': appointment.dateTime.add(const Duration(days: 1)),
          'In a week, same time': appointment.dateTime.add(const Duration(days: 7)),
          'In two weeks, same time': appointment.dateTime.add(const Duration(days: 14)),
        };
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Reschedule',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final entry in options.entries)
                ListTile(
                  leading: const Icon(Icons.arrow_forward),
                  title: Text(entry.key),
                  subtitle: Text(_formatDay(entry.value)),
                  onTap: () => Navigator.of(sheetContext).pop(entry.value),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Pick a date and time...'),
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (choice == null) {
      // "Pick a date and time" (or a dismissed sheet) falls through to the
      // full editor, which is the same thing with every field available.
      await _openEditor(existing: appointment, existingPatient: patient);
      return;
    }

    final allowed = await _confirmNoClash(
      dateTime: choice,
      durationMinutes: appointment.durationMinutes,
      ignoreAppointmentId: appointment.id,
    );
    if (!allowed || !mounted) return;

    final updated = appointment.copyWith(dateTime: choice);
    await widget.repository.updateAppointment(updated);
    await NotificationService.instance.cancelReminder(appointment.id!);
    if (patient != null) {
      await NotificationService.instance.scheduleReminder(updated, patient);
    }
    if (!mounted) return;
    setState(() {
      _selectedDay = DateTime(choice.year, choice.month, choice.day);
      _focusedMonth = DateTime(choice.year, choice.month);
      _load();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved to ${_formatDay(choice)} at ${_formatTimeOfDay(choice)}.')),
    );
  }

  Future<void> _openFollowUp(Appointment appointment, Patient? patient) async {
    if (patient == null) return;
    final days = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Follow-up for ${patient.fullName}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final entry in _kFollowUpDays.entries)
              ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: Text(entry.key),
                subtitle: Text(
                  _formatDay(appointment.dateTime.add(Duration(days: entry.value))),
                ),
                onTap: () => Navigator.of(sheetContext).pop(entry.value),
              ),
          ],
        ),
      ),
    );
    if (days == null || !mounted) return;

    final when = appointment.dateTime.add(Duration(days: days));
    final allowed = await _confirmNoClash(
      dateTime: when,
      durationMinutes: appointment.durationMinutes,
    );
    if (!allowed || !mounted) return;

    final saved = await widget.repository.addAppointment(
      Appointment(
        patientId: appointment.patientId,
        dateTime: when,
        durationMinutes: appointment.durationMinutes,
        notes: appointment.notes,
        reminderMinutesBefore: appointment.reminderMinutesBefore,
        createdAt: DateTime.now(),
      ),
    );
    await NotificationService.instance.scheduleReminder(saved, patient);
    if (!mounted) return;
    setState(() {
      _selectedDay = DateTime(when.year, when.month, when.day);
      _focusedMonth = DateTime(when.year, when.month);
      _load();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Follow-up booked for ${_formatDay(when)}.')),
    );
  }

  Future<void> _openChart(Patient patient) async {
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
  }

  /// Deleting is undoable rather than confirmed up front - one tap to cancel
  /// a booking, one tap to put it back if that was a mistake.
  Future<void> _delete(Appointment appointment, Patient? patient) async {
    await widget.repository.deleteAppointment(appointment.id!);
    await NotificationService.instance.cancelReminder(appointment.id!);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cancelled ${patient?.fullName ?? 'appointment'} on ${_formatDay(appointment.dateTime)}.',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final restored = await widget.repository.addAppointment(
              Appointment(
                patientId: appointment.patientId,
                dateTime: appointment.dateTime,
                durationMinutes: appointment.durationMinutes,
                notes: appointment.notes,
                reminderMinutesBefore: appointment.reminderMinutesBefore,
                createdAt: appointment.createdAt,
              ),
            );
            if (patient != null) {
              await NotificationService.instance.scheduleReminder(restored, patient);
            }
            if (mounted) _reload();
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: _todayButtonKey,
              onPressed: _jumpToToday,
              icon: const Icon(Icons.today_outlined, size: 20),
              label: const Text('Today'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<_AppointmentsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Text('Could not load appointments.'));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SegmentedButton<AppointmentsView>(
                  key: _viewToggleKey,
                  segments: const [
                    ButtonSegment(
                      value: AppointmentsView.agenda,
                      label: Text('Agenda'),
                      icon: Icon(Icons.view_agenda_outlined),
                    ),
                    ButtonSegment(
                      value: AppointmentsView.month,
                      label: Text('Month'),
                      icon: Icon(Icons.calendar_month_outlined),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (selection) =>
                      setState(() => _viewMode = selection.first),
                ),
              ),
              Expanded(
                child: _viewMode == AppointmentsView.agenda
                    ? _buildAgenda(data)
                    : _buildMonth(data),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: _newAppointmentKey,
        onPressed: () => _openEditor(
          initialDay: _viewMode == AppointmentsView.month ? _selectedDay : null,
        ),
        icon: const Icon(Icons.add),
        label: const Text('New appointment'),
      ),
    );
  }

  Widget _buildAgenda(_AppointmentsData data) {
    final now = DateTime.now();
    final filtered = data.appointments.where((appt) {
      final end = appt.dateTime.add(Duration(minutes: appt.durationMinutes));
      return switch (_filter) {
        _AgendaFilter.upcoming => end.isAfter(now),
        _AgendaFilter.past => end.isBefore(now),
        _AgendaFilter.all => true,
      };
    }).toList()..sort((a, b) => _filter == _AgendaFilter.past
        ? b.dateTime.compareTo(a.dateTime)
        : a.dateTime.compareTo(b.dateTime));

    final groups = <DateTime, List<Appointment>>{};
    for (final appt in filtered) {
      final day = DateTime(appt.dateTime.year, appt.dateTime.month, appt.dateTime.day);
      groups.putIfAbsent(day, () => []).add(appt);
    }

    // The heading "Today" scrolls to: today's own, or the next day with
    // something on it if today is empty.
    final today = DateTime(now.year, now.month, now.day);
    final todayAnchor = groups.keys
        .where((day) => !day.isBefore(today))
        .fold<DateTime?>(null, (best, day) => best == null || day.isBefore(best) ? day : best);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final filter in _AgendaFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (filter) {
                      _AgendaFilter.upcoming => 'Upcoming',
                      _AgendaFilter.past => 'Past',
                      _AgendaFilter.all => 'All',
                    }),
                    selected: _filter == filter,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(switch (_filter) {
                    _AgendaFilter.upcoming => 'Nothing booked yet. Tap + to schedule a visit.',
                    _AgendaFilter.past => 'No past appointments.',
                    _AgendaFilter.all => 'No appointments yet. Tap + to add one.',
                  }),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  children: [
                    for (final day in groups.keys) ...[
                      Padding(
                        key: day == todayAnchor ? _agendaTodayKey : null,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _formatRelativeDay(day),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final appt in groups[day]!)
                        _AppointmentCard(
                          appointment: appt,
                          patient: data.patientsById[appt.patientId],
                          onTap: () => _openOptions(appt, data),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMonth(_AppointmentsData data) {
    final countsByDay = <DateTime, int>{};
    for (final appt in data.appointments) {
      final day = DateTime(appt.dateTime.year, appt.dateTime.month, appt.dateTime.day);
      countsByDay.update(day, (value) => value + 1, ifAbsent: () => 1);
    }
    final selected = data.onDay(_selectedDay);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      children: [
        _MonthGrid(
          focusedMonth: _focusedMonth,
          selectedDay: _selectedDay,
          countsByDay: countsByDay,
          onMonthChanged: (month) => setState(() => _focusedMonth = month),
          onDaySelected: (day) => setState(() => _selectedDay = day),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _formatRelativeDay(_selectedDay),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _openEditor(initialDay: _selectedDay),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Book'),
            ),
          ],
        ),
        if (selected.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Nothing booked on this day.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          for (final appt in selected)
            _AppointmentCard(
              appointment: appt,
              patient: data.patientsById[appt.patientId],
              onTap: () => _openOptions(appt, data),
            ),
      ],
    );
  }
}

/// A month grid with a dot on every day that has bookings. Hand-rolled so
/// the app keeps its own look and gains no calendar dependency.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.focusedMonth,
    required this.selectedDay,
    required this.countsByDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Map<DateTime, int> countsByDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month);
    final daysInMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    // DateTime.weekday is Mon=1..Sun=7, and the grid starts on Monday.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final cellCount = ((leadingBlanks + daysInMonth) / 7).ceil() * 7;
    final today = DateTime.now();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => onMonthChanged(
                    DateTime(focusedMonth.year, focusedMonth.month - 1),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${_monthNames[focusedMonth.month - 1]} ${focusedMonth.year}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => onMonthChanged(
                    DateTime(focusedMonth.year, focusedMonth.month + 1),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in _weekdayInitials)
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemCount: cellCount,
              itemBuilder: (context, index) {
                final dayNumber = index - leadingBlanks + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final day = DateTime(focusedMonth.year, focusedMonth.month, dayNumber);
                final isSelected = _isSameDay(day, selectedDay);
                final isToday = _isSameDay(day, today);
                final count = countsByDay[day] ?? 0;

                return InkWell(
                  onTap: () => onDaySelected(day),
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? theme.colorScheme.primary : null,
                        border: isToday && !isSelected
                            ? Border.all(color: theme.colorScheme.primary)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNumber',
                            style: TextStyle(
                              color: isSelected ? theme.colorScheme.onPrimary : null,
                              fontWeight: isToday ? FontWeight.w700 : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 4,
                            child: count == 0
                                ? null
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      for (var i = 0; i < (count > 3 ? 3 : count); i++)
                                        Container(
                                          width: 4,
                                          height: 4,
                                          margin: const EdgeInsets.symmetric(horizontal: 1),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelected
                                                ? theme.colorScheme.onPrimary
                                                : theme.colorScheme.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.patient,
    required this.onTap,
  });

  final Appointment appointment;
  final Patient? patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = appointment.dateTime.add(Duration(minutes: appointment.durationMinutes));
    final isPast = end.isBefore(DateTime.now());

    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatTimeOfDay(appointment.dateTime),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPast ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
              Text(
                '${appointment.durationMinutes}m',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        title: Text(
          patient?.fullName ?? 'Unknown patient',
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          appointment.notes.isEmpty
              ? 'Until ${_formatTimeOfDay(end)}'
              : appointment.notes,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (appointment.reminderMinutesBefore != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Reminder set',
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const Icon(Icons.more_vert),
          ],
        ),
        onTap: onTap,
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
  const _AppointmentFormDialog({
    required this.repository,
    required this.syncService,
    this.existing,
    this.existingPatient,
    this.initialDay,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final Appointment? existing;
  final Patient? existingPatient;
  final DateTime? initialDay;

  @override
  State<_AppointmentFormDialog> createState() => _AppointmentFormDialogState();
}

class _AppointmentFormDialogState extends State<_AppointmentFormDialog> {
  Patient? _selectedPatient;
  late DateTime _date;
  late TimeOfDay _time;
  late int _duration;
  late final TextEditingController _notesController;
  int? _reminderMinutesBefore;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedPatient = widget.existingPatient;
    if (existing == null) _preselectSolePatient();
    final dt = existing?.dateTime ??
        widget.initialDay?.add(const Duration(hours: 9)) ??
        DateTime.now().add(const Duration(hours: 1));
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

  /// A one-dentist practice with a single patient on file shouldn't have to
  /// pick that patient every time. Asking for two rows answers "is there
  /// exactly one?" without reading the whole table.
  Future<void> _preselectSolePatient() async {
    final firstFew = await widget.repository.searchPatients('', limit: 2);
    if (!mounted || firstFew.length != 1 || _selectedPatient != null) return;
    setState(() => _selectedPatient = firstFew.first);
  }

  Future<void> _pickPatient() async {
    final picked = await showPatientPicker(
      context,
      repository: widget.repository,
      syncService: widget.syncService,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedPatient = picked);
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
    final theme = Theme.of(context);
    final end = _combinedDateTime.add(Duration(minutes: _duration));
    final today = DateTime.now();
    final dialogWidth = kDialogContentWidth(context);
    const chipSpacing = 8.0;
    // Three time chips per row, not four: at four, a dialog on a phone left
    // each chip too narrow for "09:30" and the labels were cut off.
    const timeColumns = 3;
    final timeChipWidth =
        (dialogWidth - chipSpacing * (timeColumns - 1)) / timeColumns;
    final isCustomTime = !_kQuickTimes.any(
      (slot) => slot.hour == _time.hour && slot.minute == _time.minute,
    );
    final quickDays = <String, DateTime>{
      'Today': DateTime(today.year, today.month, today.day),
      'Tomorrow': DateTime(today.year, today.month, today.day + 1),
      'Next week': DateTime(today.year, today.month, today.day + 7),
    };

    return AlertDialog(
      title: Text(widget.existing == null ? 'New appointment' : 'Edit appointment'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.existing == null)
                // A search-and-add picker rather than a dropdown: a dropdown
                // means scrolling every patient in the practice, and offers
                // no way to book someone who isn't on file yet.
                InkWell(
                  onTap: _pickPatient,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Patient',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.search),
                      helperText: 'Tap to search, or add a new patient',
                    ),
                    isEmpty: _selectedPatient == null,
                    child: _selectedPatient == null
                        ? null
                        : Text(
                            _selectedPatient!.fullName,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                )
              else
                Text('Patient: ${_selectedPatient?.fullName ?? 'Unknown'}'),
              const SizedBox(height: 16),
              Text('Day', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              // Equal-width chips on a grid so the rows share one right edge
              // instead of ending wherever the label happens to stop.
              Row(
                children: [
                  for (final entry in quickDays.entries) ...[
                    Expanded(
                      child: ChoiceChip(
                        label: _ChipLabel(entry.key),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        selected: _isSameDay(_date, entry.value),
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _date = entry.value),
                      ),
                    ),
                    if (entry.key != quickDays.keys.last)
                      const SizedBox(width: chipSpacing),
                  ],
                ],
              ),
              const SizedBox(height: chipSpacing),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_formatDay(_date)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Time', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: chipSpacing,
                runSpacing: chipSpacing,
                children: [
                  for (final slot in _kQuickTimes)
                    SizedBox(
                      width: timeChipWidth,
                      child: ChoiceChip(
                        label: _ChipLabel(_formatTime(slot)),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        selected: _time.hour == slot.hour && _time.minute == slot.minute,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _time = slot),
                      ),
                    ),
                  SizedBox(
                    width: timeChipWidth,
                    child: ChoiceChip(
                      // Shows the chosen time once it's one the quick slots
                      // don't cover, so a custom time isn't invisible.
                      label: _ChipLabel(isCustomTime ? _formatTime(_time) : 'Other...'),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                      selected: isCustomTime,
                      showCheckmark: false,
                      onSelected: (_) => _pickTime(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Booked ${_formatTimeOfDay(_combinedDateTime)} - ${_formatTimeOfDay(end)} '
                'on ${_formatDay(_date)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
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

/// A chip label for chips laid out on a fixed-width grid. Because the width
/// is fixed by the grid rather than by the text, a label that doesn't quite
/// fit has to shrink - otherwise it gets clipped mid-character and "09:30"
/// reads as "09:3".
class _ChipLabel extends StatelessWidget {
  const _ChipLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
      ),
    );
  }
}

const List<String> _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatDay(DateTime day) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${weekdays[day.weekday - 1]}, ${day.year}-${two(day.month)}-${two(day.day)}';
}

/// Day headings read as "Today"/"Tomorrow"/"Yesterday" where that helps, and
/// fall back to the full date otherwise.
String _formatRelativeDay(DateTime day) {
  final now = DateTime.now();
  if (_isSameDay(day, now)) return 'Today';
  if (_isSameDay(day, now.add(const Duration(days: 1)))) return 'Tomorrow';
  if (_isSameDay(day, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return _formatDay(day);
}

String _formatTimeOfDay(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

String _formatTime(TimeOfDay time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}
