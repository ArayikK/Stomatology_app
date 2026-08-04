import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../dicom/dicom_image_converter.dart';
import '../dicom/dicom_parser.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';

/// Bottom-sheet content for one tooth: view/edit its notes and its x-rays.
class ToothDetailSheet extends StatefulWidget {
  const ToothDetailSheet({
    super.key,
    required this.repository,
    required this.syncService,
    required this.patientId,
    required this.toothNumber,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final int patientId;
  final int toothNumber;

  @override
  State<ToothDetailSheet> createState() => _ToothDetailSheetState();
}

class _ToothDetailSheetState extends State<ToothDetailSheet> {
  List<ToothNote> _notes = [];
  List<ToothImage> _images = [];
  bool _loading = true;
  final _newNoteController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newNoteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final notes = await widget.repository.getNotes(
      widget.patientId,
      widget.toothNumber,
    );
    final images = await widget.repository.getImages(
      widget.patientId,
      widget.toothNumber,
    );
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _images = images;
      _loading = false;
    });
  }

  Future<void> _addNote() async {
    final text = _newNoteController.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    await widget.repository.addNote(widget.patientId, widget.toothNumber, text);
    _newNoteController.clear();
    await _load();
    if (mounted) setState(() => _busy = false);
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _editNote(ToothNote note) async {
    final controller = TextEditingController(text: note.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit note'),
          content: TextField(
            controller: controller,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newText == null || newText.trim().isEmpty) return;
    await widget.repository.updateNote(note, newText);
    await _load();
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _deleteNote(ToothNote note) async {
    if (note.id == null) return;
    await widget.repository.deleteNote(note.id!);
    await _load();
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    final docsDir = await getApplicationDocumentsDirectory();
    final xraysDir = Directory(p.join(docsDir.path, 'xrays'));
    if (!await xraysDir.exists()) {
      await xraysDir.create(recursive: true);
    }
    final ext = p.extension(picked.path);
    final fileName =
        'p${widget.patientId}_t${widget.toothNumber}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final savedPath = p.join(xraysDir.path, fileName);
    await File(picked.path).copy(savedPath);
    await widget.repository.addImage(widget.patientId, widget.toothNumber, savedPath);
    await _load();
    if (mounted) setState(() => _busy = false);
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _pickDicomFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dcm'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) return; // user cancelled the picker

    if (picked.bytes == null) {
      await _showDicomError('Could not read the selected file.');
      return;
    }

    setState(() => _busy = true);
    try {
      final dataset = const DicomParser().parse(picked.bytes!);
      final rendered = await const DicomImageConverter().convert(dataset);

      final docsDir = await getApplicationDocumentsDirectory();
      final xraysDir = Directory(p.join(docsDir.path, 'xrays'));
      if (!await xraysDir.exists()) {
        await xraysDir.create(recursive: true);
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final baseName = 'p${widget.patientId}_t${widget.toothNumber}_$stamp';
      final displayPath = p.join(xraysDir.path, '$baseName.${rendered.extension}');
      final originalPath = p.join(xraysDir.path, '$baseName.dcm');
      await File(displayPath).writeAsBytes(rendered.bytes);
      await File(originalPath).writeAsBytes(picked.bytes!);

      await widget.repository.addImage(
        widget.patientId,
        widget.toothNumber,
        displayPath,
        originalDicomPath: originalPath,
      );
      await _load();
      unawaited(widget.syncService.pushAll());
    } on DicomParseException catch (e) {
      await _showDicomError(e.message);
    } catch (e) {
      await _showDicomError('Could not import this DICOM file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bottom sheets can visually swallow SnackBars (they render behind the
  /// still-open sheet), so DICOM import errors use a dialog instead - it's
  /// impossible to miss.
  Future<void> _showDicomError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Couldn\'t import this file'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _viewImage(ToothImage image) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.file(File(image.filePath), fit: BoxFit.contain),
              ),
              if (image.originalDicomPath != null)
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Imported from DICOM',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteImage(ToothImage image) async {
    if (image.id == null) return;
    await widget.repository.deleteImage(image.id!);
    await _load();
    unawaited(widget.syncService.pushAll());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Tooth ${widget.toothNumber}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text('X-rays', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final image in _images)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _viewImage(image),
                          onLongPress: () => _deleteImage(image),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(image.filePath),
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              if (image.originalDicomPath != null)
                                Positioned(
                                  left: 4,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'DICOM',
                                      style: TextStyle(color: Colors.white, fontSize: 9),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    _AddImageButton(
                      busy: _busy,
                      onPickGallery: () => _pickImage(ImageSource.gallery),
                      onPickCamera: () => _pickImage(ImageSource.camera),
                      onPickDicom: _pickDicomFile,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Notes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_notes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No work recorded on this tooth yet.'),
                ),
              for (final note in _notes)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(note.text),
                    subtitle: Text(_formatDate(note.updatedAt)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editNote(note),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteNote(note),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newNoteController,
                      decoration: const InputDecoration(
                        hintText: 'Describe work done on this tooth...',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _addNote,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _ImageSourceChoice { gallery, camera, dicom }

class _AddImageButton extends StatelessWidget {
  const _AddImageButton({
    required this.busy,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickDicom,
  });

  final bool busy;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickDicom;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: OutlinedButton(
        onPressed: busy
            ? null
            : () async {
                final source = await showModalBottomSheet<_ImageSourceChoice>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.photo_library_outlined),
                          title: const Text('Choose from gallery'),
                          onTap: () => Navigator.of(context).pop(_ImageSourceChoice.gallery),
                        ),
                        ListTile(
                          leading: const Icon(Icons.photo_camera_outlined),
                          title: const Text('Take photo'),
                          onTap: () => Navigator.of(context).pop(_ImageSourceChoice.camera),
                        ),
                        ListTile(
                          leading: const Icon(Icons.folder_zip_outlined),
                          title: const Text('Import DICOM (.dcm)'),
                          subtitle: const Text('X-ray export from a dental sensor/PACS'),
                          onTap: () => Navigator.of(context).pop(_ImageSourceChoice.dicom),
                        ),
                      ],
                    ),
                  ),
                );
                switch (source) {
                  case _ImageSourceChoice.gallery:
                    onPickGallery();
                  case _ImageSourceChoice.camera:
                    onPickCamera();
                  case _ImageSourceChoice.dicom:
                    onPickDicom();
                  case null:
                    break;
                }
              },
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
