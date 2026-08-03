import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dental_repository.dart';
import 'device_identity.dart';

/// Talks to the backend in backend/ - see backend/README.md. Every call is
/// best-effort: an offline/unreachable backend must never block or crash
/// the app, since all data already lives locally first.
class BackendSyncService {
  BackendSyncService({required this.repository, http.Client? client})
    : _client = client ?? http.Client();

  final DentalRepository repository;
  final http.Client _client;

  /// Update this once the backend is deployed (see backend/README.md step 3).
  static const String baseUrl = 'https://stom-backend.onrender.com';

  Future<bool> pushAll() async {
    try {
      final deviceId = await DeviceIdentity.get();
      final payload = await _buildPayload();
      final response = await _client
          .put(
            Uri.parse('$baseUrl/api/user/$deviceId'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'data': payload}),
          )
          .timeout(const Duration(seconds: 20));
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
      for (var number = 1; number <= 32; number++) {
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
          });
        }

        teeth.add({
          'toothNumber': number,
          'notes': [
            for (final note in notes)
              {
                'text': note.text,
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
          await repository.addImage(patient.id!, toothNumber, filePath);
        }
      }
      restoredCount++;
    }
    return restoredCount;
  }
}
