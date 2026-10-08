import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../models/annotation_shape.dart';
import '../models/image_view_settings.dart';
import '../models/note_category.dart';
import '../models/patient.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';
import '../reports/xray_report.dart';
import 'dialog_metrics.dart';
import 'image_compare_screen.dart';
import 'image_viewer_screen.dart';
import 'xray_import_flow.dart';
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
  Patient? _patient;
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
    final patient = await widget.repository.getPatient(widget.patientId);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _images = images;
      _patient = patient;
      _loading = false;
    });
  }

  /// Oldest first: the x-ray strip reads as a timeline of this tooth.
  List<ToothImage> get _imagesOldestFirst {
    final sorted = List<ToothImage>.of(_images)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sorted;
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

  /// Adding an image goes through the shared flow, so this screen and the
  /// patient's x-ray tab always offer the same sources and behave the same.
  Future<void> _addImage() async {
    final source = await showXraySourceSheet(context);
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    final added = await runXrayImport(
      context: context,
      repository: widget.repository,
      syncService: widget.syncService,
      patientId: widget.patientId,
      toothNumber: widget.toothNumber,
      source: source,
    );
    if (added) await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _viewImage(ToothImage image) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          repository: widget.repository,
          syncService: widget.syncService,
          image: image,
          siblings: _images,
          patient: _patient,
          notes: _notes,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _comparePair((ToothImage, ToothImage) pair) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageCompareScreen(left: pair.$1, right: pair.$2),
      ),
    );
  }

  /// One PDF for this tooth: every image with its markings burned in, plus
  /// the written history. What gets handed to the patient, sent to a
  /// colleague, or filed with an insurer.
  Future<void> _sharePdfReport() async {
    final patient = _patient;
    if (patient == null) return;
    setState(() => _busy = true);
    try {
      final reportImages = <ReportImage>[];
      for (final image in _imagesOldestFirst) {
        final png = await renderAnnotatedPng(
          file: File(image.filePath),
          shapes: decodeAnnotations(image.annotationsJson),
          settings: ImageViewSettings.decode(image.viewSettingsJson),
          mmPerPixel: image.pixelSpacingMm,
        );
        if (png != null) {
          reportImages.add(ReportImage(png: png, caption: describeReportImage(image)));
        }
      }
      final pdf = await buildToothReportPdf(
        patient: patient,
        toothNumber: widget.toothNumber,
        images: reportImages,
        notes: _notes,
      );
      await Printing.sharePdf(
        bytes: pdf,
        filename: 'tooth-${widget.toothNumber}-${patient.lastName.toLowerCase()}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not build the report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      appBar: AppBar(
        title: Text('Tooth ${widget.toothNumber}'),
        actions: [
          IconButton(
            tooltip: 'Share as PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _busy || _patient == null ? null : _sharePdfReport,
          ),
        ],
      ),
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
                  height: 124,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final image in _imagesOldestFirst)
                        _XrayStripItem(
                          caption: _formatShortDate(image.createdAt),
                          onTap: () => _viewImage(image),
                          onLongPress: () => _deleteImage(image),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(image.filePath), fit: BoxFit.cover),
                              if (image.originalDicomPath != null && !image.isSeries)
                                const Positioned(
                                  left: 4,
                                  bottom: 4,
                                  child: _Badge(text: 'DICOM', small: true),
                                ),
                              if (image.isSeries)
                                Positioned(
                                  left: 4,
                                  bottom: 4,
                                  child: _Badge(
                                    text: '${image.sliceCount} sl.',
                                    small: true,
                                  ),
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
                      _XrayStripItem(
                        key: _addImageKey,
                        caption: 'Add',
                        onTap: _busy ? null : _addImage,
                        child: _AddImagePlaceholder(busy: _busy),
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
                          IconButton(
                            tooltip: 'Compare side by side',
                            icon: const Icon(Icons.compare_arrows),
                            onPressed: () => _comparePair(pair),
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

/// One cell of the x-ray strip. Thumbnails and the "add" placeholder are
/// built from the same tile, so the placeholder is exactly the same square
/// as a real image instead of a differently shaped box next to them.
class _XrayStripItem extends StatelessWidget {
  const _XrayStripItem({
    super.key,
    required this.child,
    required this.caption,
    this.onTap,
    this.onLongPress,
  });

  static const double tileSize = 96;

  final Widget child;
  final String caption;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: child,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: tileSize,
              child: Text(
                caption,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddImagePlaceholder extends StatelessWidget {
  const _AddImagePlaceholder({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Center(
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.add_a_photo_outlined, color: scheme.primary),
      ),
    );
  }
}

String _formatShortDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
