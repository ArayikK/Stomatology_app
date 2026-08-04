import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment.dart';
import '../models/patient.dart';

/// Wraps flutter_local_notifications for appointment reminders. Scheduling
/// is best-effort: a failure here (permission denied, platform quirk)
/// should never block saving an appointment, since the appointment itself
/// is already safely stored locally either way.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings: settings);

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // Permission prompts can fail/be denied - reminders just won't fire.
    }

    _initialized = true;
  }

  Future<void> scheduleReminder(Appointment appointment, Patient patient) async {
    final appointmentId = appointment.id;
    final minutesBefore = appointment.reminderMinutesBefore;
    if (appointmentId == null || minutesBefore == null) return;

    final fireAt = appointment.dateTime.subtract(Duration(minutes: minutesBefore));
    if (fireAt.isBefore(DateTime.now())) return;

    try {
      await init();
      final scheduled = tz.TZDateTime.from(fireAt.toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        id: appointmentId,
        title: 'Upcoming appointment',
        body: '${patient.fullName} at ${_formatTime(appointment.dateTime)}',
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'appointment_reminders',
            'Appointment reminders',
            channelDescription: 'Reminders for upcoming patient appointments',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // Best-effort; the appointment itself is already saved regardless.
    }
  }

  Future<void> cancelReminder(int appointmentId) async {
    try {
      await _plugin.cancel(id: appointmentId);
    } catch (_) {
      // Nothing to do if the platform can't cancel it.
    }
  }
}

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
