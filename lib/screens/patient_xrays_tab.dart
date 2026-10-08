import 'dart:io';

import 'package:flutter/material.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/patient.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';
import 'image_viewer_screen.dart';
import 'xray_import_flow.dart';

/// Images that belong to the patient rather than to one tooth: panoramic
/// films, CBCT scans, face photos. They are stored on the same "general"
/// tooth number the whole-mouth timeline entries use, so nothing new was
/// needed in the database for them.
class PatientXraysTab extends StatefulWidget {
  const PatientXraysTab({
    super.key,
    required this.repository,
    required this.syncService,
    required this.patient,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final Patient patient;

  @override
  State<PatientXraysTab> createState() => _PatientXraysTabState();
}

class _PatientXraysTabState extends State<PatientXraysTab> {
  List<ToothImage> _images = [];
  List<ToothNote> _notes = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final images = await widget.repository.getImages(
      widget.patient.id!,
      kGeneralToothNumber,
    );
    final notes = await widget.repository.getNotes(
      widget.patient.id!,
      kGeneralToothNumber,
    );
    if (!mounted) return;
    setState(() {
      // Oldest first: the row reads as this patient's imaging history.
      _images = images.reversed.toList();
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final source = await showXraySourceSheet(context);
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    final added = await runXrayImport(
      context: context,
      repository: widget.repository,
      syncService: widget.syncService,
      patientId: widget.patient.id!,
      toothNumber: kGeneralToothNumber,
      source: source,
    );
    if (added) await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open(ToothImage image) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          repository: widget.repository,
          syncService: widget.syncService,
          image: image,
          siblings: _images,
          patient: widget.patient,
          notes: _notes,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Add image'),
      ),
      body: _images.isEmpty
          ? _EmptyState(onAdd: _busy ? null : _add)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) => _XrayTile(
                image: _images[index],
                onTap: () => _open(_images[index]),
              ),
            ),
    );
  }
}

class _XrayTile extends StatelessWidget {
  const _XrayTile({required this.image, required this.onTap});

  final ToothImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(image.filePath), fit: BoxFit.cover),
                ),
                if (image.isSeries)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Chip(text: '${image.sliceCount} slices'),
                  ),
                if (image.originalDicomPath != null && !image.isSeries)
                  const Positioned(left: 6, top: 6, child: _Chip(text: 'DICOM')),
                if (image.hasAnnotations)
                  const Positioned(
                    right: 6,
                    bottom: 6,
                    child: Icon(Icons.draw, size: 16, color: Colors.white),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(image.createdAt),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No images for this patient yet',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Panoramic films, CBCT scans and photos of the whole mouth live '
              'here. Images of a single tooth stay on that tooth.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add image'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}
