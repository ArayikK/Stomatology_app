import 'dart:io';

import 'package:flutter/material.dart';

import '../models/annotation_shape.dart';
import '../models/image_view_settings.dart';
import '../models/tooth_image.dart';
import '../widgets/annotated_image.dart';

/// Two images of the same tooth side by side, sharing one zoom: whatever the
/// dentist zooms into on the left, the right follows. That is what makes a
/// before/after actually comparable - and it is the view patients understand
/// immediately.
class ImageCompareScreen extends StatefulWidget {
  const ImageCompareScreen({
    super.key,
    required this.left,
    required this.right,
    this.leftLabel = 'Before',
    this.rightLabel = 'After',
  });

  final ToothImage left;
  final ToothImage right;
  final String leftLabel;
  final String rightLabel;

  @override
  State<ImageCompareScreen> createState() => _ImageCompareScreenState();
}

class _ImageCompareScreenState extends State<ImageCompareScreen> {
  final TransformationController _zoom = TransformationController();
  bool _syncZoom = true;
  Size? _leftSize;
  Size? _rightSize;

  @override
  void initState() {
    super.initState();
    _loadSizes();
  }

  Future<void> _loadSizes() async {
    final left = await readImageSize(File(widget.left.filePath));
    final right = await readImageSize(File(widget.right.filePath));
    if (!mounted) return;
    setState(() {
      _leftSize = left;
      _rightSize = right;
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;
    final panels = [
      Expanded(
        child: _ComparePanel(
          image: widget.left,
          imageSize: _leftSize,
          label: '${widget.leftLabel}  ·  ${_formatDate(widget.left.createdAt)}',
          controller: _syncZoom ? _zoom : null,
        ),
      ),
      const SizedBox(width: 8, height: 8),
      Expanded(
        child: _ComparePanel(
          image: widget.right,
          imageSize: _rightSize,
          label: '${widget.rightLabel}  ·  ${_formatDate(widget.right.createdAt)}',
          controller: _syncZoom ? _zoom : null,
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Compare'),
        actions: [
          IconButton(
            tooltip: _syncZoom ? 'Zoom together' : 'Zoom separately',
            icon: Icon(_syncZoom ? Icons.link : Icons.link_off),
            onPressed: () => setState(() => _syncZoom = !_syncZoom),
          ),
          IconButton(
            tooltip: 'Reset zoom',
            icon: const Icon(Icons.zoom_out_map),
            onPressed: () => _zoom.value = Matrix4.identity(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: isWide
              ? Row(children: panels)
              : Column(children: panels),
        ),
      ),
    );
  }
}

class _ComparePanel extends StatelessWidget {
  const _ComparePanel({
    required this.image,
    required this.imageSize,
    required this.label,
    required this.controller,
  });

  final ToothImage image;
  final Size? imageSize;
  final String label;

  /// Shared with the other panel while zoom is linked; null gives this panel
  /// its own independent zoom.
  final TransformationController? controller;

  @override
  Widget build(BuildContext context) {
    final size = imageSize;
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: size == null
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(
                  transformationController: controller,
                  minScale: 1,
                  maxScale: 8,
                  child: Center(
                    child: AnnotatedImageView(
                      file: File(image.filePath),
                      imageSize: size,
                      shapes: decodeAnnotations(image.annotationsJson),
                      settings: ImageViewSettings.decode(image.viewSettingsJson),
                      mmPerPixel: image.pixelSpacingMm,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d.$m.${date.year}';
}
