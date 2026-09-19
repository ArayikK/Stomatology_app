import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../dicom/dicom_image_converter.dart';
import '../dicom/dicom_parser.dart';
import '../models/annotation_shape.dart';
import '../models/note_category.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';
import 'dialog_metrics.dart';
import 'image_annotation_screen.dart';
import '../tour/app_tour.dart';
import '../tour/spotlight_tour.dart';

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

  final GlobalKey _xraysKey = GlobalKey();
  final GlobalKey _addImageKey = GlobalKey();
  final GlobalKey _notesKey = GlobalKey();
  final GlobalKey _addNoteKey = GlobalKey();

  List<TourStep> get _tourSteps => [
    TourStep(
      target: _xraysKey,
      title: 'X-rays & photos',
      body: 'Every image for this tooth. Tap one to view it full screen, draw annotations on it, '
          'or pair a before and after shot.',
      pad: 8,
    ),
    TourStep(
      target: _addImageKey,
      title: 'Add an image',
      body: 'Take a photo, pick one from the gallery, or import a DICOM (.dcm) x-ray from your sensor.',
      pad: 6,
    ),
    TourStep(
      target: _notesKey,
      title: 'Treatment notes',
      body: 'Each note has a category and keeps its edit history, so earlier versions are never lost.',
      pad: 8,
    ),
    TourStep(
      target: _addNoteKey,
      title: 'Add a note',
      body: 'Type it, or tap the microphone in the editor and dictate hands-free.',
      pad: 6,
    ),
  ];

  List<(ToothImage, ToothImage)> get _beforeAfterPairs {
    final pairs = <(ToothImage, ToothImage)>[];
    for (final before in _images.where((i) => i.role == ImageRole.before)) {
      final matches = _images.where((i) => i.id == before.pairedImageId);
      if (matches.isNotEmpty) pairs.add((before, matches.first));
    }
    return pairs;
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted) AppTour.maybeShow(context, TourScreen.tooth, _tourSteps);
    });
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
    final speech = stt.SpeechToText();
    var isListening = false;
    var dictationBase = '';

    final result = await showDialog<_NoteEditResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> toggleDictation() async {
              if (isListening) {
                await speech.stop();
                setDialogState(() => isListening = false);
                return;
              }
              final available = await speech.initialize();
              if (!available) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Speech recognition isn\'t available on this device.')),
                  );
                }
                return;
              }
              dictationBase = controller.text;
              setDialogState(() => isListening = true);
              await speech.listen(
                onResult: (result) {
                  final spoken = result.recognizedWords;
                  controller.text = dictationBase.isEmpty ? spoken : '$dictationBase $spoken';
                  controller.selection = TextSelection.collapsed(offset: controller.text.length);
                  if (result.finalResult) setDialogState(() => isListening = false);
                },
              );
            }

            // The dialog is given one explicit width so the category grid,
            // the note field and the buttons all share the same edges - an
            // AlertDialog otherwise sizes itself to its widest child.
            final dialogWidth = kDialogContentWidth(context);
            const chipSpacing = 8.0;
            final chipColumns = dialogWidth >= 380 ? 3 : 2;
            final chipWidth =
                (dialogWidth - chipSpacing * (chipColumns - 1)) / chipColumns;

            return AlertDialog(
              title: Text(existing == null ? 'Add note' : 'Edit note'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: dialogWidth,
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Category', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    // Equal-width chips laid out on a grid: a plain Wrap left a
                    // ragged right edge, and any size change on selection would
                    // reflow the rows.
                    Wrap(
                      spacing: chipSpacing,
                      runSpacing: chipSpacing,
                      children: [
                        for (final category in NoteCategory.values)
                          SizedBox(
                            width: chipWidth,
                            child: ChoiceChip(
                              label: Center(
                                child: Text(
                                  category.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              selected: selectedCategory == category,
                              // Selection shows purely through colour - a
                              // checkmark would shift the label off-centre.
                              showCheckmark: false,
                              selectedColor: category.color.withValues(alpha: 0.35),
                              side: BorderSide(
                                color: category.color.withValues(
                                  alpha: selectedCategory == category ? 0.9 : 0.4,
                                ),
                              ),
                              onSelected: (_) =>
                                  setDialogState(() => selectedCategory = category),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: existing == null,
                      minLines: 4,
                      maxLines: 10,
                      decoration: InputDecoration(
                        hintText: 'Describe the work done on this tooth...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: isListening ? 'Stop dictation' : 'Dictate note',
                          icon: Icon(
                            isListening ? Icons.mic : Icons.mic_none,
                            color: isListening ? Theme.of(context).colorScheme.error : null,
                          ),
                          onPressed: toggleDictation,
                        ),
                      ),
                    ),
                    if (isListening)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Listening...',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    if (isListening) await speech.stop();
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

  Future<void> _showNoteHistory(ToothNote note) async {
    if (note.id == null) return;
    final history = await widget.repository.getNoteHistory(note.id!);
    if (!mounted) return;
    if (history.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit history'),
          content: const Text('This note hasn\'t been edited yet.'),
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

    final reverted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit history'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: history.length,
            separatorBuilder: (context, index) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final entry = history[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CategoryChip(category: entry.category),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatDate(entry.editedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(entry.text),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        await widget.repository.revertNoteToHistoryEntry(note, entry);
                        if (context.mounted) Navigator.of(context).pop(true);
                      },
                      child: const Text('Revert to this version'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (reverted == true) {
      await _load();
      unawaited(widget.syncService.pushAll());
    }
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    InteractiveViewer(
                      child: Image.file(File(image.filePath), fit: BoxFit.contain),
                    ),
                    if (image.originalDicomPath != null)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: _Badge(text: 'Imported from DICOM'),
                      ),
                    if (image.role != null)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: _Badge(
                          text: image.role == ImageRole.before ? 'BEFORE' : 'AFTER',
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
              ),
              OverflowBar(
                alignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _annotateImage(image);
                    },
                    icon: const Icon(Icons.draw_outlined),
                    label: Text(image.hasAnnotations ? 'Edit annotations' : 'Annotate'),
                  ),
                  if (image.isPaired)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await widget.repository.unpairImage(image.id!);
                        await _load();
                        unawaited(widget.syncService.pushAll());
                      },
                      icon: const Icon(Icons.link_off),
                      label: const Text('Unpair'),
                    )
                  else
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _pairImageFlow(image);
                      },
                      icon: const Icon(Icons.compare),
                      label: const Text('Pair as before/after'),
                    ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _deleteImage(image);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pairImageFlow(ToothImage image) async {
    final candidates = _images.where((i) => i.id != image.id && !i.isPaired).toList();
    if (candidates.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nothing to pair with'),
          content: const Text(
            'Add another x-ray/photo for this tooth first, then you can link the two '
            'as a before/after comparison.',
          ),
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

    final partner = await showDialog<ToothImage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pair with which image?'),
        children: [
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(candidate),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(candidate.filePath),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_formatDate(candidate.createdAt)),
                ],
              ),
            ),
        ],
      ),
    );
    if (partner == null || !mounted) return;

    final role = await showDialog<ImageRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which one is "before"?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ImageRole.before),
            child: const Text('This image is the "before"'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ImageRole.after),
            child: const Text('This image is the "after"'),
          ),
        ],
      ),
    );
    if (role == null) return;

    if (role == ImageRole.before) {
      await widget.repository.pairImages(beforeImageId: image.id!, afterImageId: partner.id!);
    } else {
      await widget.repository.pairImages(beforeImageId: partner.id!, afterImageId: image.id!);
    }
    await _load();
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _deleteImage(ToothImage image) async {
    if (image.id == null) return;
    await widget.repository.deleteImage(image.id!);
    await _load();
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _annotateImage(ToothImage image) async {
    final shapes = await Navigator.of(context).push<List<AnnotationShape>>(
      MaterialPageRoute(
        builder: (context) => ImageAnnotationScreen(
          imageFile: File(image.filePath),
          initialShapes: decodeAnnotations(image.annotationsJson),
        ),
      ),
    );
    if (shapes == null || image.id == null) return;
    await widget.repository.updateImageAnnotations(image.id!, shapes);
    await _load();
    unawaited(widget.syncService.pushAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tooth ${widget.toothNumber}')),
      floatingActionButton: FloatingActionButton.extended(
        key: _addNoteKey,
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
                  key: _xraysKey,
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
                                  const Positioned(
                                    left: 4,
                                    bottom: 4,
                                    child: _Badge(text: 'DICOM', small: true),
                                  ),
                                if (image.role != null)
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: _Badge(
                                      text: image.role == ImageRole.before ? 'B' : 'A',
                                      small: true,
                                    ),
                                  ),
                                if (image.hasAnnotations)
                                  const Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Icon(Icons.draw, color: Colors.white, size: 14),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      _AddImageButton(
                        key: _addImageKey,
                        busy: _busy,
                        onPickGallery: () => _pickImage(ImageSource.gallery),
                        onPickCamera: () => _pickImage(ImageSource.camera),
                        onPickDicom: _pickDicomFile,
                      ),
                    ],
                  ),
                ),
                if (_beforeAfterPairs.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Before / After',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final pair in _beforeAfterPairs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: _ComparisonThumb(image: pair.$1, onTap: _viewImage)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.arrow_forward),
                          ),
                          Expanded(child: _ComparisonThumb(image: pair.$2, onTap: _viewImage)),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Text('Notes', key: _notesKey, style: Theme.of(context).textTheme.titleMedium),
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
                                tooltip: 'Edit history',
                                icon: const Icon(Icons.history, size: 20),
                                onPressed: () => _showNoteHistory(note),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6, vertical: small ? 1 : 3),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: Colors.white, fontSize: small ? 9 : 11),
      ),
    );
  }
}

class _ComparisonThumb extends StatelessWidget {
  const _ComparisonThumb({required this.image, required this.onTap});

  final ToothImage image;
  final ValueChanged<ToothImage> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(image),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.file(File(image.filePath), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            image.role == ImageRole.before ? 'Before' : 'After',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
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
    super.key,
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
