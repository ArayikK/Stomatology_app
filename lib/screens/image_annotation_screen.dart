import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation_shape.dart';

const List<String> _kPalette = ['#FF3B30', '#FFD60A', '#34C759', '#0A84FF', '#FFFFFF'];

/// Draw freehand marks/lines and take pixel-distance measurements on top of
/// an x-ray/photo. The original image file is never modified - shapes are
/// stored separately and composited on top every time the image is shown.
class ImageAnnotationScreen extends StatefulWidget {
  const ImageAnnotationScreen({
    super.key,
    required this.imageFile,
    required this.initialShapes,
  });

  final File imageFile;
  final List<AnnotationShape> initialShapes;

  @override
  State<ImageAnnotationScreen> createState() => _ImageAnnotationScreenState();
}

class _ImageAnnotationScreenState extends State<ImageAnnotationScreen> {
  late List<AnnotationShape> _shapes;
  AnnotationShape? _activeShape;
  AnnotationTool _tool = AnnotationTool.freehand;
  String _colorHex = _kPalette.first;
  Size? _imageSize;
  late final ImageStream _stream;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _shapes = List.of(widget.initialShapes);
    _stream = FileImage(widget.imageFile).resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, synchronousCall) {
      if (!mounted) return;
      setState(() {
        _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
      });
    });
    _stream.addListener(_listener);
  }

  @override
  void dispose() {
    _stream.removeListener(_listener);
    super.dispose();
  }

  Offset _clamp01(Offset o) => Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));

  void _onPanStart(Offset local, Size box) {
    final normalized = _clamp01(Offset(local.dx / box.width, local.dy / box.height));
    setState(() {
      _activeShape = AnnotationShape(tool: _tool, points: [normalized], colorHex: _colorHex);
    });
  }

  void _onPanUpdate(Offset local, Size box) {
    final shape = _activeShape;
    if (shape == null) return;
    final normalized = _clamp01(Offset(local.dx / box.width, local.dy / box.height));
    setState(() {
      _activeShape = _tool == AnnotationTool.freehand
          ? shape.withAddedPoint(normalized)
          : shape.withEndPoint(normalized);
    });
  }

  void _onPanEnd() {
    final shape = _activeShape;
    if (shape != null && shape.points.length >= 2) {
      setState(() {
        _shapes = [..._shapes, shape];
        _activeShape = null;
      });
    } else {
      setState(() => _activeShape = null);
    }
  }

  void _undo() {
    if (_shapes.isEmpty) return;
    setState(() => _shapes = _shapes.sublist(0, _shapes.length - 1));
  }

  Future<void> _clearAll() async {
    if (_shapes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all annotations?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) setState(() => _shapes = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Annotate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _shapes.isEmpty ? null : _undo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _shapes.isEmpty ? null : _clearAll,
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_shapes),
            child: const Text('SAVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _imageSize == null
                  ? const CircularProgressIndicator()
                  : AspectRatio(
                      aspectRatio: _imageSize!.width / _imageSize!.height,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final box = constraints.biggest;
                          return ClipRect(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(widget.imageFile, fit: BoxFit.fill),
                                GestureDetector(
                                  onPanStart: (d) => _onPanStart(d.localPosition, box),
                                  onPanUpdate: (d) => _onPanUpdate(d.localPosition, box),
                                  onPanEnd: (_) => _onPanEnd(),
                                  child: CustomPaint(
                                    size: box,
                                    painter: AnnotationPainter(
                                      shapes: [..._shapes, ?_activeShape],
                                      imageSize: _imageSize!,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ToolButton(
                        icon: Icons.edit,
                        label: 'Draw',
                        selected: _tool == AnnotationTool.freehand,
                        onTap: () => setState(() => _tool = AnnotationTool.freehand),
                      ),
                      _ToolButton(
                        icon: Icons.show_chart,
                        label: 'Line',
                        selected: _tool == AnnotationTool.line,
                        onTap: () => setState(() => _tool = AnnotationTool.line),
                      ),
                      _ToolButton(
                        icon: Icons.straighten,
                        label: 'Measure',
                        selected: _tool == AnnotationTool.measurement,
                        onTap: () => setState(() => _tool = AnnotationTool.measurement),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final hex in _kPalette)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _colorHex = hex),
                            child: CircleAvatar(
                              radius: _colorHex == hex ? 14 : 11,
                              backgroundColor: Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16)),
                              child: _colorHex == hex
                                  ? const Icon(Icons.check, size: 14, color: Colors.black)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : Colors.white70;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: color),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Renders [shapes] (normalized 0..1 coordinates) into pixel coordinates
/// for a canvas of the given [size]. [imageSize] is the image's natural
/// pixel dimensions, used only to compute measurement distances.
class AnnotationPainter extends CustomPainter {
  const AnnotationPainter({required this.shapes, required this.imageSize});

  final List<AnnotationShape> shapes;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    Offset toPixel(Offset normalized) =>
        Offset(normalized.dx * size.width, normalized.dy * size.height);

    for (final shape in shapes) {
      if (shape.points.isEmpty) continue;
      final paint = Paint()
        ..color = shape.color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      switch (shape.tool) {
        case AnnotationTool.freehand:
          if (shape.points.length < 2) continue;
          final path = Path()..moveTo(toPixel(shape.points.first).dx, toPixel(shape.points.first).dy);
          for (final p in shape.points.skip(1)) {
            final px = toPixel(p);
            path.lineTo(px.dx, px.dy);
          }
          canvas.drawPath(path, paint);
        case AnnotationTool.line:
          if (shape.points.length < 2) continue;
          canvas.drawLine(toPixel(shape.points.first), toPixel(shape.points.last), paint);
        case AnnotationTool.measurement:
          if (shape.points.length < 2) continue;
          final start = toPixel(shape.points.first);
          final end = toPixel(shape.points.last);
          canvas.drawLine(start, end, paint);
          final dx = (shape.points.last.dx - shape.points.first.dx) * imageSize.width;
          final dy = (shape.points.last.dy - shape.points.first.dy) * imageSize.height;
          final distance = math.sqrt(dx * dx + dy * dy).round();
          final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
          final textPainter = TextPainter(
            text: TextSpan(
              text: '${distance}px',
              style: TextStyle(
                color: shape.color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.black54,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          textPainter.paint(canvas, mid - Offset(textPainter.width / 2, textPainter.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}
