import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../legal/legal_content.dart';
import '../models/appointment.dart';
import '../models/patient.dart';
import '../models/patient_summary.dart';
import 'appointments_screen.dart';
import 'faq_screen.dart';
import 'legal_document_screen.dart';
import 'patient_chart_screen.dart';
import 'patient_list_screen.dart';
import '../tour/app_tour.dart';
import '../tour/spotlight_tour.dart';

/// Above this width the dashboard splits into two columns.
const double _wideLayoutBreakpoint = 840;

/// How many recently worked-on patients the dashboard lists.
const int _recentPatientLimit = 5;

enum _MenuAction { tour, privacy, terms, faq }

/// The app's landing page: a "today at a glance" dashboard - today's
/// schedule, practice counters, quick actions, and the patients most
/// recently worked on. Everything else (full patient list, calendar) is one
/// tap away from here.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.syncService,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _DashboardData {
  const _DashboardData({
    required this.summaries,
    required this.appointments,
    required this.patientsById,
  });

  final List<PatientSummary> summaries;
  final List<Appointment> appointments;
  final Map<int, Patient> patientsById;

  int get patientCount => summaries.length;

  List<Appointment> get todaysAppointments {
    final now = DateTime.now();
    return appointments
        .where((a) => _isSameDay(a.dateTime, now))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  /// Appointments still to come in the next seven days, today included.
  List<Appointment> get upcomingWeek {
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 7));
    return appointments
        .where((a) => a.dateTime.isAfter(now) && a.dateTime.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  Appointment? get nextAppointment {
    final now = DateTime.now();
    final future = appointments.where((a) => a.dateTime.isAfter(now)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return future.isEmpty ? null : future.first;
  }

  List<PatientSummary> get recentlySeen {
    final seen = summaries.where((s) => s.lastActivity != null).toList()
      ..sort((a, b) => b.lastActivity!.compareTo(a.lastActivity!));
    return seen.take(_recentPatientLimit).toList();
  }
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_DashboardData> _dataFuture;

  final GlobalKey _greetingKey = GlobalKey();
  final GlobalKey _statsKey = GlobalKey();
  final GlobalKey _todayKey = GlobalKey();
  final GlobalKey _recentKey = GlobalKey();
  final GlobalKey _backupKey = GlobalKey();
  final GlobalKey _menuKey = GlobalKey();

  List<TourStep> get _tourSteps => [
    TourStep(
      target: _greetingKey,
      title: 'Your day at a glance',
      body: 'Every time you open Stom you land here, with your next appointment up top.',
      pad: 10,
    ),
    TourStep(
      target: _statsKey,
      title: 'Practice numbers',
      body: 'Patients on file, visits today and visits this week. Tap a number to open that list.',
      pad: 10,
    ),
    TourStep(
      target: _todayKey,
      title: "Today's schedule",
      body: 'Visits booked for today. Tap one to jump to that patient.',
      pad: 10,
    ),
    TourStep(
      target: _recentKey,
      title: 'Recently seen',
      body: 'The patients you worked on last, one tap away.',
      pad: 10,
    ),
    TourStep(
      target: _backupKey,
      title: 'Cloud backup',
      body: 'Everything is saved on this device and backed up online automatically, no account needed. '
          'The cloud turns red if a backup fails. Tap it to back up now.',
      pad: 4,
    ),
    TourStep(
      target: _menuKey,
      title: 'Menu',
      body: 'Replay this tour any time, and find the FAQ and privacy policy here.',
      pad: 4,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    _dataFuture.then((_) {
      if (mounted) AppTour.maybeShow(context, TourScreen.home, _tourSteps);
    }, onError: (_) {});
  }

  Future<void> _replayTour() async {
    await AppTour.restart();
    if (!mounted) return;
    await AppTour.show(context, TourScreen.home, _tourSteps);
  }

  Future<_DashboardData> _loadData() async {
    final summaries = await widget.repository.getPatientSummaries();
    final appointments = await widget.repository.getAllAppointments();
    return _DashboardData(
      summaries: summaries,
      appointments: appointments,
      patientsById: {
        for (final s in summaries)
          if (s.patient.id != null) s.patient.id!: s.patient,
      },
    );
  }

  void _reload() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _openPatientList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PatientListScreen(
          repository: widget.repository,
          syncService: widget.syncService,
        ),
      ),
    );
    _reload();
  }

  Future<void> _openAppointments({
    AppointmentsView view = AppointmentsView.agenda,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AppointmentsScreen(
          repository: widget.repository,
          syncService: widget.syncService,
          initialView: view,
        ),
      ),
    );
    _reload();
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

  void _handleMenuAction(_MenuAction action) {
    switch (action) {
      case _MenuAction.tour:
        _replayTour();
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
        title: const Text('Stom'),
        actions: [
          _BackupStatusButton(key: _backupKey, syncService: widget.syncService),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          PopupMenuButton<_MenuAction>(
            key: _menuKey,
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _MenuAction.tour, child: Text('App tour')),
              PopupMenuItem(value: _MenuAction.privacy, child: Text('Privacy Policy')),
              PopupMenuItem(value: _MenuAction.terms, child: Text('Terms & Conditions')),
              PopupMenuItem(value: _MenuAction.faq, child: Text('FAQ')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<_DashboardData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return _LoadFailed(onRetry: _reload, error: snapshot.error);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= _wideLayoutBreakpoint;
              if (!isWide) {
                // Not a lazy ListView: the tour needs every card built so it
                // can scroll to and spotlight any of them.
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GreetingHeader(key: _greetingKey, data: data),
                    const SizedBox(height: 16),
                    _StatRow(
                      key: _statsKey,
                      data: data,
                      onOpenPatients: _openPatientList,
                      onOpenAppointments: _openAppointments,
                    ),
                    const SizedBox(height: 16),
                    _TodayScheduleCard(
                      key: _todayKey,
                      data: data,
                      onOpenAppointments: _openAppointments,
                      onOpenPatient: _openChart,
                    ),
                    const SizedBox(height: 16),
                    _RecentPatientsCard(
                      key: _recentKey,
                      data: data,
                      onOpenPatients: _openPatientList,
                      onOpenPatient: _openChart,
                    ),
                  ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GreetingHeader(key: _greetingKey, data: data),
                    const SizedBox(height: 20),
                    _StatRow(
                      key: _statsKey,
                      data: data,
                      onOpenPatients: _openPatientList,
                      onOpenAppointments: _openAppointments,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _TodayScheduleCard(
                            key: _todayKey,
                            data: data,
                            onOpenAppointments: _openAppointments,
                            onOpenPatient: _openChart,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _RecentPatientsCard(
                            key: _recentKey,
                            data: data,
                            onOpenPatients: _openPatientList,
                            onOpenPatient: _openChart,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Cloud icon in the app bar showing whether the latest backup reached the
/// backend. Tapping it runs a backup right away.
class _BackupStatusButton extends StatelessWidget {
  const _BackupStatusButton({super.key, required this.syncService});

  final BackendSyncService syncService;

  static String _describeLastSuccess(DateTime? at) {
    if (at == null) return 'Never backed up';
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) return 'Last backup: just now';
    if (elapsed.inHours < 1) return 'Last backup: ${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) return 'Last backup: ${elapsed.inHours} h ago';
    return 'Last backup: ${elapsed.inDays} d ago';
  }

  Future<void> _backUpNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Backing up…')));
    final ok = await syncService.pushAll();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Backup complete' : 'Backup failed. Check your internet connection.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: syncService.status,
      builder: (context, status, _) {
        final lastSuccess = _describeLastSuccess(status.lastSuccessAt);
        final (IconData icon, String tooltip, Color? color) = switch (status.state) {
          SyncState.syncing => (Icons.cloud_upload_outlined, 'Backing up…', null),
          SyncState.failed => (
            Icons.cloud_off_outlined,
            'Backup failed. $lastSuccess',
            Theme.of(context).colorScheme.error,
          ),
          SyncState.synced => (Icons.cloud_done_outlined, lastSuccess, null),
          SyncState.idle => (Icons.cloud_outlined, lastSuccess, null),
        };
        return IconButton(
          tooltip: '$tooltip\nTap to back up now',
          icon: Icon(icon, color: color),
          onPressed: status.state == SyncState.syncing ? null : () => _backUpNow(context),
        );
      },
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry, this.error});

  final VoidCallback onRetry;

  /// Shown behind "Details" so a user hitting this on their own device can
  /// read back what actually went wrong.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Could not load your practice data.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            if (error != null) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Details'),
                tilePadding: EdgeInsets.zero,
                children: [
                  SelectableText(
                    '$error',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({super.key, required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final next = data.nextAppointment;
    final nextPatient =
        next == null ? null : data.patientsById[next.patientId]?.fullName;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greetingFor(now),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatFullDate(now),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  next == null ? Icons.event_available_outlined : Icons.schedule,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    next == null
                        ? 'No upcoming appointments scheduled.'
                        : 'Next: ${nextPatient ?? 'Unknown patient'} - '
                              '${_formatRelativeDay(next.dateTime)} at '
                              '${_formatTimeOfDay(next.dateTime)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The three counters. Each one opens the screen it counts, so the numbers
/// double as navigation.
class _StatRow extends StatelessWidget {
  const _StatRow({
    super.key,
    required this.data,
    required this.onOpenPatients,
    required this.onOpenAppointments,
  });

  final _DashboardData data;
  final VoidCallback onOpenPatients;
  final void Function({AppointmentsView view}) onOpenAppointments;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.people_outline,
            value: '${data.patientCount}',
            label: 'Patients',
            onTap: onOpenPatients,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.today_outlined,
            value: '${data.todaysAppointments.length}',
            label: 'Today',
            onTap: () => onOpenAppointments(view: AppointmentsView.month),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.date_range_outlined,
            value: '${data.upcomingWeek.length}',
            label: 'Next 7 days',
            onTap: () => onOpenAppointments(view: AppointmentsView.agenda),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayScheduleCard extends StatelessWidget {
  const _TodayScheduleCard({
    super.key,
    required this.data,
    required this.onOpenAppointments,
    required this.onOpenPatient,
  });

  final _DashboardData data;
  final VoidCallback onOpenAppointments;
  final void Function(Patient patient) onOpenPatient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = data.todaysAppointments;
    final now = DateTime.now();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: "Today's schedule",
            actionLabel: 'Calendar',
            onAction: onOpenAppointments,
          ),
          if (today.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Text(
                'Nothing scheduled for today.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final appt in today)
              ListTile(
                leading: SizedBox(
                  width: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatTimeOfDay(appt.dateTime),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: appt.dateTime.isBefore(now)
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                      Text('${appt.durationMinutes}m', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                title: Text(
                  data.patientsById[appt.patientId]?.fullName ?? 'Unknown patient',
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: appt.notes.isEmpty
                    ? null
                    : Text(appt.notes, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final patient = data.patientsById[appt.patientId];
                  if (patient == null) return;
                  onOpenPatient(patient);
                },
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RecentPatientsCard extends StatelessWidget {
  const _RecentPatientsCard({
    super.key,
    required this.data,
    required this.onOpenPatients,
    required this.onOpenPatient,
  });

  final _DashboardData data;
  final VoidCallback onOpenPatients;
  final void Function(Patient patient) onOpenPatient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = data.recentlySeen;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Recently seen',
            actionLabel: 'See all',
            onAction: onOpenPatients,
          ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Text(
                data.patientCount == 0
                    ? 'No patients yet. Add your first one above.'
                    : 'No treatment recorded yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final summary in recent)
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    summary.patient.firstName.isNotEmpty
                        ? summary.patient.firstName[0]
                        : '?',
                  ),
                ),
                title: Text(
                  summary.patient.fullName,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('Last visit: ${_formatDate(summary.lastActivity!)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenPatient(summary.patient),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

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

String _formatFullDate(DateTime date) {
  final local = date.toLocal();
  return '${_weekdayNames[local.weekday - 1]}, '
      '${_monthNames[local.month - 1]} ${local.day}, ${local.year}';
}

/// "today"/"tomorrow" for the near future, an explicit date beyond that.
String _formatRelativeDay(DateTime date) {
  final now = DateTime.now();
  if (_isSameDay(date, now)) return 'today';
  if (_isSameDay(date, now.add(const Duration(days: 1)))) return 'tomorrow';
  final local = date.toLocal();
  return '${_monthNames[local.month - 1]} ${local.day}';
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

String _formatTimeOfDay(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
