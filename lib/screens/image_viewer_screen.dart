import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../data/backend_sync_service.dart';
import '../data/dental_repository.dart';
import '../data/xray_import.dart';
import '../models/annotation_shape.dart';
import '../models/image_view_settings.dart';
import '../models/patient.dart';
import '../models/tooth_image.dart';
import '../models/tooth_note.dart';
import '../reports/xray_report.dart';
import '../widgets/annotated_image.dart';
import 'image_annotation_screen.dart';
import 'image_compare_screen.dart';

/// Full-screen view of one x-ray: zoom, brightness/contrast, the slice
/// slider for a CBCT series, and everything that can be done with the image
/// (annotate, compare, pair, export, delete).
///
/// Pops `true` when anything was changed, so the caller knows to reload.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.repository,
    required this.syncService,
    required this.image,
    required this.siblings,
    required this.patient,
    required this.notes,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;
  final ToothImage image;

  /// The other images of the same tooth - what "compare" and "pair" offer.
  final List<ToothImage> siblings;
  final Patient? patient;
  final List<ToothNote> notes;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late ToothImage _image;
  late ImageViewSettings _settings;
  late List<AnnotationShape> _shapes;
  late int _slice;

  Size? _imageSize;
  bool _changed = false;

  /// Open from the start: on an x-ray the first thing a dentist reaches for
  /// is brightness/contrast (and "negative" on a CBCT slice), so the panel
  /// is there rather than one tap away. The button in the app bar hides it
  /// again when the image should fill the screen.
  bool _showAdjust = true;
  bool _busy = false;
  Timer? _saveSettings;

  final TransformationController _zoom = TransformationController();

  @override
  void initState() {
    super.initState();
    _image = widget.image;
    _settings = ImageViewSettings.decode(_image.viewSettingsJson);
    _shapes = decodeAnnotations(_image.annotationsJson);
    _slice = _initialSlice();
    _loadSize();
  }

  int _initialSlice() {
    if (!_image.isSeries) return 0;
    final digits = RegExp(r'(\d+)\.png$').firstMatch(p.basename(_image.filePath));
    final parsed = digits == null ? null : int.tryParse(digits.group(1)!);
    return parsed ?? (_image.sliceCount! ~/ 2);
  }

  Future<void> _loadSize() async {
    final size = await readImageSize(_currentFile);
    if (!mounted) return;
    setState(() => _imageSize = size);
  }

  @override
  void dispose() {
    _saveSettings?.cancel();
    _zoom.dispose();
    super.dispose();
  }

  File get _currentFile => _image.isSeries
      ? File(slicePath(_image.seriesDir!, _slice))
      : File(_image.filePath);

  /// Settings change on every slider tick, so the write is debounced rather
  /// than hitting the database dozens of times per drag.
  void _queueSettingsSave() {
    _saveSettings?.cancel();
    _saveSettings = Timer(const Duration(milliseconds: 400), () async {
      if (_image.id == null) return;
      await widget.repository.updateImageViewSettings(_image.id!, _settings);
      _changed = true;
      unawaited(widget.syncService.pushAll());
    });
  }

  Future<void> _annotate() async {
    final result = await Navigator.of(context).push<AnnotationEditResult>(
      MaterialPageRoute(
        builder: (context) => ImageAnnotationScreen(
          imageFile: _currentFile,
          initialShapes: _shapes,
          initialSettings: _settings,
          mmPerPixel: _image.pixelSpacingMm,
        ),
      ),
    );
    if (result == null || _image.id == null) return;
    await widget.repository.updateImageAnnotations(_image.id!, result.shapes);
    await widget.repository.updateImageViewSettings(_image.id!, result.settings);
    if (result.mmPerPixel != _image.pixelSpacingMm) {
      await widget.repository.updateImageCalibration(_image.id!, result.mmPerPixel);
    }
    final refreshed = await widget.repository.getImage(_image.id!);
    if (!mounted) return;
    setState(() {
      _shapes = result.shapes;
      _settings = result.settings;
      if (refreshed != null) _image = refreshed;
      _changed = true;
    });
    unawaited(widget.syncService.pushAll());
  }

  Future<void> _compare() async {
    final partner = _image.pairedImageId != null
        ? widget.siblings.where((i) => i.id == _image.pairedImageId).firstOrNull
        : await _pickSibling('Compare with which image?');
    if (partner == null || !mounted) return;
    final thisIsBefore = _image.role != ImageRole.after;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageCompareScreen(
          left: thisIsBefore ? _image : partner,
          right: thisIsBefore ? partner : _image,
          leftLabel: _image.role == null ? 'Left' : 'Before',
          rightLabel: _image.role == null ? 'Right' : 'After',
        ),
      ),
    );
  }

  Future<ToothImage?> _pickSibling(String title) {
    final candidates = widget.siblings.where((i) => i.id != _image.id).toList();
    if (candidates.isEmpty) {
      return showDialog<ToothImage>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nothing to compare with'),
          content: const Text('Add another image for this tooth first.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return showDialog<ToothImage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
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
  }

  Future<void> _exportPdf() async {
    final patient = widget.patient;
    if (patient == null) return;
    setState(() => _busy = true);
    try {
      final png = await renderAnnotatedPng(
        file: _currentFile,
        shapes: _shapes,
        settings: _settings,
        mmPerPixel: _image.pixelSpacingMm,
      );
      final pdf = await buildToothReportPdf(
        patient: patient,
        toothNumber: _image.toothNumber,
        images: [
          if (png != null)
            ReportImage(png: png, caption: describeReportImage(_image)),
        ],
        notes: widget.notes,
      );
      await Printing.sharePdf(
        bytes: pdf,
        filename: 'tooth-${_image.toothNumber}-${patient.lastName.toLowerCase()}.pdf',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this image?'),
        content: const Text('The image and its annotations are removed from this tooth.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || _image.id == null || !mounted) return;
    await widget.repository.deleteImage(_image.id!);
    unawaited(widget.syncService.pushAll());
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _togglePair() async {
    if (_image.id == null) return;
    if (_image.isPaired) {
      await widget.repository.unpairImage(_image.id!);
    } else {
      final partner = await _pickSibling('Pair with which image?');
      if (partner?.id == null || !mounted) return;
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
        await widget.repository.pairImages(
          beforeImageId: _image.id!,
          afterImageId: partner!.id!,
        );
      } else {
        await widget.repository.pairImages(
          beforeImageId: partner!.id!,
          afterImageId: _image.id!,
        );
      }
    }
    final refreshed = await widget.repository.getImage(_image.id!);
    if (!mounted) return;
    setState(() {
      if (refreshed != null) _image = refreshed;
      _changed = true;
    });
    unawaited(widget.syncService.pushAll());
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _imageSize;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(_formatDate(_image.createdAt)),
          actions: [
            IconButton(
              tooltip: 'Brightness & contrast',
              icon: Icon(_showAdjust ? Icons.tune : Icons.tune_outlined),
              onPressed: () => setState(() => _showAdjust = !_showAdjust),
            ),
            IconButton(
              tooltip: 'Annotate',
              icon: const Icon(Icons.draw_outlined),
              onPressed: _annotate,
            ),
            IconButton(
              tooltip: 'Compare',
              icon: const Icon(Icons.compare),
              onPressed: _compare,
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'pair':
                    _togglePair();
                  case 'pdf':
                    _exportPdf();
                  case 'reset':
                    setState(() {
                      _settings = ImageViewSettings.none;
                      _zoom.value = Matrix4.identity();
                    });
                    _queueSettingsSave();
                  case 'delete':
                    _delete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'pair',
                  child: Text(_image.isPaired ? 'Unpair before/after' : 'Pair as before/after'),
                ),
                if (widget.patient != null)
                  const PopupMenuItem(value: 'pdf', child: Text('Share as PDF')),
                const PopupMenuItem(value: 'reset', child: Text('Reset view')),
                const PopupMenuItem(value: 'delete', child: Text('Delete image')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: imageSize == null
                        ? const CircularProgressIndicator()
                        : InteractiveViewer(
                            transformationController: _zoom,
                            minScale: 1,
                            maxScale: 8,
                            child: AnnotatedImageView(
                              file: _currentFile,
                              imageSize: imageSize,
                              shapes: _shapes,
                              settings: _settings,
                              mmPerPixel: _image.pixelSpacingMm,
                            ),
                          ),
                  ),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (_image.originalDicomPath != null) const _Tag('DICOM'),
                        if (_image.isCalibrated)
                          _Tag('${_image.pixelSpacingMm!.toStringAsFixed(3)} mm/px')
                        else
                          const _Tag('no scale'),
                        if (_image.role != null)
                          _Tag(_image.role == ImageRole.before ? 'BEFORE' : 'AFTER'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_image.isSeries) _buildSliceSlider(),
            if (_showAdjust) _buildAdjustPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildSliceSlider() {
    final count = _image.sliceCount!;
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            'Slice ${_slice + 1}/$count',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Expanded(
            child: Slider(
              value: _slice.toDouble(),
              min: 0,
              max: (count - 1).toDouble(),
              divisions: count > 1 ? count - 1 : null,
              onChanged: (value) => setState(() => _slice = value.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustPanel() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.brightness_6_outlined, color: Colors.white70, size: 18),
                Expanded(
                  child: Slider(
                    value: _settings.brightness,
                    min: -1,
                    max: 1,
                    onChanged: (value) {
                      setState(() => _settings = _settings.copyWith(brightness: value));
                      _queueSettingsSave();
                    },
                  ),
                ),
                const Icon(Icons.contrast, color: Colors.white70, size: 18),
                Expanded(
                  child: Slider(
                    value: _settings.contrast,
                    min: -1,
                    max: 1,
                    onChanged: (value) {
                      setState(() => _settings = _settings.copyWith(contrast: value));
                      _queueSettingsSave();
                    },
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() => _settings = _settings.copyWith(inverted: !_settings.inverted));
                    _queueSettingsSave();
                  },
                  icon: Icon(
                    _settings.inverted ? Icons.invert_colors : Icons.invert_colors_off,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text('Negative', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
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

String _formatDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d.$m.${date.year}';
}
