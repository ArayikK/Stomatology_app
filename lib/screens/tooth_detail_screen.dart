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
import '../models/note_category.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';

/// Full page for one tooth: its x-rays and its notes. A full page rather
/// than a popup/bottom sheet, since a tooth can accumulate a lot of
/// history and cramming that into a half-screen sheet reads as cluttered.
class ToothDetailScreen extends StatefulWidget {
  const ToothDetailScreen({
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
  State<ToothDetailScreen> createState() => _ToothDetailScreenState();
}

class _ToothDetailScreenState extends State<ToothDetailScreen> {
  List<ToothNote> _notes = [];
  List<ToothImage> _images = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await widget.repository.getNotes(widget.patientId, widget.toothNumber);
    final images = await widget.repository.getImages(widget.patientId, widget.toothNumber);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _images = images;
      _loading = false;
    });
  }

  Future<void> _showNoteEditor({ToothNote? existing}) async {
    final controller = TextEditingController(text: existing?.text ?? '');
    var selectedCategory = existing?.category ?? NoteCategory.other;

    final result = await showDialog<_NoteEditResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add note' : 'Edit note'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Category', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in NoteCategory.values)
                          ChoiceChip(
                            label: Text(category.label),
                            selected: selectedCategory == category,
                            selectedColor: category.color.withValues(alpha: 0.3),
                            side: BorderSide(color: category.color.withValues(alpha: 0.5)),
                            onSelected: (_) => setDialogState(() => selectedCategory = category),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: existing == null,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        hintText: 'Describe the work done on this tooth...',
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
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_NoteEditResult(controller.text, selectedCategory)),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (result == null || result.text.trim().isEmpty) return;

    if (existing == null) {
      await widget.repository.addNote(
        widget.patientId,
        widget.toothNumber,
        result.text,
        category: result.category,
      );
    } else {
      await widget.repository.updateNote(existing, result.text, category: result.category);
    }
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
    return Scaffold(
      appBar: AppBar(title: Text('Tooth ${widget.toothNumber}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add note'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
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
                const SizedBox(height: 24),
                Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_notes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No work recorded on this tooth yet.'),
                  ),
                for (final note in _notes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: note.category.color.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _CategoryChip(category: note.category),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formatDate(note.updatedAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _showNoteEditor(existing: note),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => _deleteNote(note),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _ExpandableNoteText(text: note.text),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NoteEditResult {
  const _NoteEditResult(this.text, this.category);
  final String text;
  final NoteCategory category;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final NoteCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        category.label,
        style: TextStyle(color: category.color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Long notes get truncated with a "Show more" toggle instead of pushing
/// everything else down the page.
class _ExpandableNoteText extends StatefulWidget {
  const _ExpandableNoteText({required this.text});
  final String text;

  @override
  State<_ExpandableNoteText> createState() => _ExpandableNoteTextState();
}

class _ExpandableNoteTextState extends State<_ExpandableNoteText> {
  static const _collapsedCharLimit = 160;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > _collapsedCharLimit;
    final displayText = (!_expanded && isLong)
        ? '${widget.text.substring(0, _collapsedCharLimit).trimRight()}…'
        : widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayText),
        if (isLong)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _expanded ? 'Show less' : 'Show more',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
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
