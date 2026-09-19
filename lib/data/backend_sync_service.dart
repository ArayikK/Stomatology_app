import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/annotation_shape.dart';
import '../models/note_category.dart';
import '../models/tooth_note.dart';
import 'dental_repository.dart';
import 'device_identity.dart';

enum SyncState { idle, syncing, synced, failed }

class SyncStatus {
  const SyncStatus(this.state, {this.lastSuccessAt});

  final SyncState state;

  /// When a backup last reached the backend, or null if never.
  final DateTime? lastSuccessAt;
}

/// Talks to the backend in backend/ - see backend/README.md. Every call is
/// best-effort: an offline/unreachable backend must never block or crash
/// the app, since all data already lives locally first.
class BackendSyncService {
  BackendSyncService({required this.repository, http.Client? client})
    : _client = client ?? http.Client();

  final DentalRepository repository;
  final http.Client _client;

  static const String baseUrl = 'https://stomatology-app.onrender.com';

  /// The free Render instance sleeps when idle and has been measured taking
  /// ~70 s to wake up, so anything shorter makes the first request after a
  /// quiet period fail.
  static const Duration _requestTimeout = Duration(seconds: 90);
  static const int _pushAttempts = 2;
  static const String _lastSuccessPrefsKey = 'stom_last_backup_at';

  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus(SyncState.idle));

  Future<bool>? _pushInFlight;
  bool _pushQueued = false;

  /// Loads the last backup time and pings the backend so a sleeping server
  /// starts waking up before the first real backup is needed.
  Future<void> warmUp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_lastSuccessPrefsKey);
      final lastSuccessAt = saved == null ? null : DateTime.tryParse(saved);
      if (lastSuccessAt != null && status.value.lastSuccessAt == null) {
        status.value = SyncStatus(status.value.state, lastSuccessAt: lastSuccessAt);
      }
    } catch (_) {}
    try {
      await _client.get(Uri.parse('$baseUrl/')).timeout(_requestTimeout);
    } catch (_) {}
  }

  /// Uploads the full local dataset. Calls made while an upload is running
  /// don't start a parallel one; they schedule a single follow-up upload so
  /// the latest edits are always sent.
  Future<bool> pushAll() {
    final inFlight = _pushInFlight;
    if (inFlight != null) {
      _pushQueued = true;
      return inFlight;
    }
    final push = _pushWithRetry();
    _pushInFlight = push;
    return push;
  }

  Future<bool> _pushWithRetry() async {
    var succeeded = false;
    try {
      do {
        _pushQueued = false;
        status.value = SyncStatus(SyncState.syncing, lastSuccessAt: status.value.lastSuccessAt);
        succeeded = false;
        for (var attempt = 0; attempt < _pushAttempts && !succeeded; attempt++) {
          succeeded = await _pushOnce();
        }
        if (succeeded) {
          final now = DateTime.now();
          status.value = SyncStatus(SyncState.synced, lastSuccessAt: now);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_lastSuccessPrefsKey, now.toIso8601String());
          } catch (_) {}
        } else {
          status.value = SyncStatus(SyncState.failed, lastSuccessAt: status.value.lastSuccessAt);
        }
      } while (_pushQueued);
    } finally {
      _pushInFlight = null;
    }
    return succeeded;
  }

  Future<bool> _pushOnce() async {
    try {
      final deviceId = await DeviceIdentity.get();
      final payload = await _buildPayload();
      final response = await _client
          .put(
            Uri.parse('$baseUrl/api/user/$deviceId'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'data': payload}),
          )
          .timeout(_requestTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> pullAll() async {
    try {
      final deviceId = await DeviceIdentity.get();
      final response = await _client
          .get(Uri.parse('$baseUrl/api/user/$deviceId'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return decoded['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _buildPayload() async {
    final patients = await repository.getPatients();
    final patientPayloads = <Map<String, dynamic>>[];
    for (final patient in patients) {
      final teeth = <Map<String, dynamic>>[];
      // Starts at kGeneralToothNumber (0), not 1: timeline entries that
      // aren't about a specific tooth live there and must sync too.
      for (var number = kGeneralToothNumber; number <= 32; number++) {
        final notes = await repository.getNotes(patient.id!, number);
        final images = await repository.getImages(patient.id!, number);
        if (notes.isEmpty && images.isEmpty) continue;

        final imagePayloads = <Map<String, dynamic>>[];
        for (final image in images) {
          final file = File(image.filePath);
          if (!await file.exists()) continue;
          imagePayloads.add({
            'fileName': p.basename(image.filePath),
            'createdAt': image.createdAt.toIso8601String(),
            'base64': base64Encode(await file.readAsBytes()),
            'annotationsJson': image.annotationsJson,
          });
        }

        teeth.add({
          'toothNumber': number,
          'notes': [
            for (final note in notes)
              {
                'text': note.text,
                'category': note.category.name,
                'createdAt': note.createdAt.toIso8601String(),
                'updatedAt': note.updatedAt.toIso8601String(),
              },
          ],
          'images': imagePayloads,
        });
      }
      patientPayloads.add({
        'firstName': patient.firstName,
        'lastName': patient.lastName,
        'allergies': patient.allergies,
        'medications': patient.medications,
        'medicalNotes': patient.medicalNotes,
        'createdAt': patient.createdAt.toIso8601String(),
        'teeth': teeth,
      });
    }
    return {
      'patients': patientPayloads,
      'syncedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Recreates local patients/notes/images from a previously pulled payload.
  /// Only ever triggered by an explicit user action (never automatically),
  /// so it never silently overwrites data the dentist is actively using.
  Future<int> restoreFromPayload(Map<String, dynamic> payload) async {
    final patients = (payload['patients'] as List?) ?? const [];
    final docsDir = await getApplicationDocumentsDirectory();
    final xraysDir = Directory(p.join(docsDir.path, 'xrays'));
    if (!await xraysDir.exists()) {
      await xraysDir.create(recursive: true);
    }

    var restoredCount = 0;
    for (final rawPatient in patients) {
      final patientMap = rawPatient as Map<String, dynamic>;
      final patient = await repository.addPatient(
        patientMap['firstName'] as String? ?? '',
        patientMap['lastName'] as String? ?? '',
      );
      await repository.updatePatientMedicalInfo(
        patient.id!,
        allergies: patientMap['allergies'] as String? ?? '',
        medications: patientMap['medications'] as String? ?? '',
        medicalNotes: patientMap['medicalNotes'] as String? ?? '',
      );
      final teeth = (patientMap['teeth'] as List?) ?? const [];
      for (final rawTooth in teeth) {
        final toothMap = rawTooth as Map<String, dynamic>;
        final toothNumber = toothMap['toothNumber'] as int;

        final notes = (toothMap['notes'] as List?) ?? const [];
        for (final rawNote in notes) {
          final noteMap = rawNote as Map<String, dynamic>;
          await repository.addNote(
            patient.id!,
            toothNumber,
            noteMap['text'] as String? ?? '',
            category: NoteCategory.fromName(noteMap['category'] as String?),
          );
        }

        final images = (toothMap['images'] as List?) ?? const [];
        for (final rawImage in images) {
          final imageMap = rawImage as Map<String, dynamic>;
          final base64Data = imageMap['base64'] as String?;
          if (base64Data == null) continue;
          final originalName = imageMap['fileName'] as String? ?? 'restored.jpg';
          final fileName =
              'p${patient.id}_t${toothNumber}_${DateTime.now().microsecondsSinceEpoch}_$originalName';
          final filePath = p.join(xraysDir.path, fileName);
          await File(filePath).writeAsBytes(base64Decode(base64Data));
          final restoredImage = await repository.addImage(patient.id!, toothNumber, filePath);
          final annotationsJson = imageMap['annotationsJson'] as String?;
          if (annotationsJson != null && annotationsJson.trim().isNotEmpty) {
            await repository.updateImageAnnotations(
              restoredImage.id!,
              decodeAnnotations(annotationsJson),
            );
          }
        }
      }
      restoredCount++;
    }
    return restoredCount;
  }
}
