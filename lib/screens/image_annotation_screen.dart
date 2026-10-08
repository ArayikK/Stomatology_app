import 'dart:io';

import 'package:flutter/material.dart';

import '../models/annotation_shape.dart';
import '../models/image_view_settings.dart';
import '../widgets/annotated_image.dart';

const List<String> _kPalette = ['#FF3B30', '#FFD60A', '#34C759', '#0A84FF', '#FFFFFF'];

/// Implant sizes offered by the template tool: the diameters and lengths
/// that cover almost every routine case.
const List<double> _kImplantDiameters = [3.0, 3.3, 3.5, 4.0, 4.5, 5.0];
const List<double> _kImplantLengths = [6, 8, 10, 11.5, 13, 16];

/// What the editor hands back: the shapes, how the image should be
/// displayed, and the scale - any of which the dentist may have changed.
class AnnotationEditResult {
  const AnnotationEditResult({
    required this.shapes,
    required this.settings,
    required this.mmPerPixel,
  });

  final List<AnnotationShape> shapes;
  final ImageViewSettings settings;
  final double? mmPerPixel;
}

/// Markup and measurement on top of an x-ray/photo: freehand notes, lengths
/// in millimetres, angles, captions, an implant template drawn to scale and
/// the mandibular canal. The image file itself is never modified - shapes
/// and display settings are stored separately and composited on top.
class ImageAnnotationScreen extends StatefulWidget {
  const ImageAnnotationScreen({
    super.key,
    required this.imageFile,
    required this.initialShapes,
    this.initialSettings = ImageViewSettings.none,
    this.mmPerPixel,
  });

  final File imageFile;
  final List<AnnotationShape> initialShapes;
  final ImageViewSettings initialSettings;

  /// Millimetres per pixel, when the image's scale is known.
  final double? mmPerPixel;

  @override
  State<ImageAnnotationScreen> createState() => _ImageAnnotationScreenState();
}

/// The editor's modes. [pan] doesn't draw: it hands gestures to the zoom
/// viewer. [calibrate] draws one line and then asks how long it really is.
enum _Mode { pan, freehand, line, measure, angle, text, implant, canal, calibrate }

class _ImageAnnotationScreenState extends State<ImageAnnotationScreen> {
  late List<AnnotationShape> _shapes;
  late ImageViewSettings _settings;
  double? _mmPerPixel;

  AnnotationShape? _activeShape;
  List<Offset> _pendingAngle = [];
  _Mode _mode = _Mode.freehand;
  String _colorHex = _kPalette.first;
  Size? _imageSize;
  bool _showAdjust = false;

  double _implantDiameter = 3.5;
  double _implantLength = 10;

  final TransformationController _zoom = TransformationController();
  late final ImageStream _stream;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _shapes = List.of(widget.initialShapes);
    _settings = widget.initialSettings;
    _mmPerPixel = widget.mmPerPixel;
    _stream = FileImage(widget.imageFile).resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, _) {
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
    _zoom.dispose();
    super.dispose();
  }

  ImageScale get _scale =>
      ImageScale(imageSize: _imageSize ?? const Size(1, 1), mmPerPixel: _mmPerPixel);

  bool get _isDrawing => _mode != _Mode.pan;

  AnnotationTool? get _toolForMode => switch (_mode) {
    _Mode.freehand => AnnotationTool.freehand,
    _Mode.line => AnnotationTool.line,
    _Mode.measure => AnnotationTool.measurement,
    _Mode.angle => AnnotationTool.angle,
    _Mode.text => AnnotationTool.text,
    _Mode.implant => AnnotationTool.implant,
    _Mode.canal => AnnotationTool.canal,
    _Mode.calibrate => AnnotationTool.measurement,
    _Mode.pan => null,
  };

  Offset _normalize(Offset local, Size box) => Offset(
    (local.dx / box.width).clamp(0.0, 1.0),
    (local.dy / box.height).clamp(0.0, 1.0),
  );

  // ---------------------------------------------------------------- drawing

  void _onPanStart(Offset local, Size box) {
    final tool = _toolForMode;
    if (tool == null || _mode == _Mode.angle) return;
    final point = _normalize(local, box);
    setState(() {
      _activeShape = AnnotationShape(
        tool: tool,
        points: [point, point],
        colorHex: _colorHex,
        implantWidthMm: _mode == _Mode.implant ? _implantDiameter : null,
        implantLengthMm: _mode == _Mode.implant ? _implantLength : null,
      );
    });
  }

  void _onPanUpdate(Offset local, Size box) {
    final shape = _activeShape;
    if (shape == null) return;
    final point = _normalize(local, box);
    setState(() {
      switch (_mode) {
        case _Mode.freehand:
        case _Mode.canal:
          _activeShape = shape.withAddedPoint(point);
        case _Mode.implant:
          _activeShape = shape.copyWith(points: [shape.points.first, _implantApex(shape.points.first, point)]);
        default:
          _activeShape = shape.withEndPoint(point);
      }
    });
  }

  /// Where the implant's tip lands: the direction comes from the drag, the
  /// length from the chosen implant, so the template is always drawn at its
  /// true size on a calibrated image.
  Offset _implantApex(Offset platform, Offset dragged) {
    final direction = dragged - platform;
    if (direction.distance == 0) return dragged;
    if (!_scale.isCalibrated) return dragged;
    final normalizedLength = _scale.normalizedLengthForMm(_implantLength, direction);
    final unit = direction / direction.distance;
    return platform + unit * normalizedLength;
  }

  Future<void> _onPanEnd() async {
    final shape = _activeShape;
    setState(() => _activeShape = null);
    if (shape == null || shape.points.length < 2) return;
    if (shape.points.first == shape.points.last) return;

    switch (_mode) {
      case _Mode.calibrate:
        await _askCalibration(shape);
      case _Mode.text:
        final label = await _askText();
        if (label == null || label.trim().isEmpty) return;
        setState(() => _shapes = [..._shapes, shape.copyWith(text: label.trim())]);
      default:
        setState(() => _shapes = [..._shapes, shape]);
    }
  }

  /// The angle tool works by tapping: arm, vertex, arm.
  void _onTap(Offset local, Size box) {
    if (_mode != _Mode.angle) return;
    final point = _normalize(local, box);
    setState(() {
      _pendingAngle = [..._pendingAngle, point];
      if (_pendingAngle.length == 3) {
        _shapes = [
          ..._shapes,
          AnnotationShape(
            tool: AnnotationTool.angle,
            points: _pendingAngle,
            colorHex: _colorHex,
          ),
        ];
        _pendingAngle = [];
      }
    });
  }

  // ------------------------------------------------------------- dialogues

  Future<String?> _askText() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. caries, cyst, fracture'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _askCalibration(AnnotationShape line) async {
    final pixels = _scale.pixelDistance(line.points.first, line.points.last);
    if (pixels < 1) return;
    final controller = TextEditingController();
    final mm = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set the scale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How long is the line you just drew, in millimetres? '
              'Use something of known size - a crown, an implant already in '
              'place, or a calibration ball.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(suffixText: 'mm'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              double.tryParse(controller.text.replaceAll(',', '.')),
            ),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (mm == null || mm <= 0) return;
    setState(() {
      _mmPerPixel = mm / pixels;
      _mode = _Mode.measure;
    });
  }

  void _undo() {
    if (_pendingAngle.isNotEmpty) {
      setState(() => _pendingAngle = _pendingAngle.sublist(0, _pendingAngle.length - 1));
      return;
    }
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

  void _save() {
    Navigator.of(context).pop(
      AnnotationEditResult(
        shapes: _shapes,
        settings: _settings,
        mmPerPixel: _mmPerPixel,
      ),
    );
  }

  // ------------------------------------------------------------------- UI

  String get _hint => switch (_mode) {
    _Mode.pan => 'Pinch to zoom, drag to move.',
    _Mode.angle => 'Tap three points: one arm, the corner, the other arm '
        '(${_pendingAngle.length}/3).',
    _Mode.text => 'Drag an arrow to what you mean, then type the label.',
    _Mode.implant => 'Drag from the crest downwards. The template is drawn at '
        'Ø$_implantDiameter × ${_implantLength.toStringAsFixed(0)} mm.',
    _Mode.canal => 'Trace the nerve canal. Implants then show how far the tip is from it.',
    _Mode.calibrate => 'Draw a line over something of known length, then type its size.',
    _Mode.measure => _scale.isCalibrated
        ? 'Drag to measure. Lengths are shown in millimetres.'
        : 'No scale on this image - measurements are in pixels. Use "Scale" to fix that.',
    _ => 'Drag to draw.',
  };

  @override
  Widget build(BuildContext context) {
    final imageSize = _imageSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Annotate'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: _shapes.isEmpty && _pendingAngle.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _shapes.isEmpty ? null : _clearAll,
          ),
          TextButton(
            onPressed: _save,
            child: const Text('SAVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: imageSize == null
                  ? const CircularProgressIndicator()
                  : _zoomable(
                      AnnotatedImageView(
                        file: widget.imageFile,
                        imageSize: imageSize,
                        shapes: [
                          ..._shapes,
                          ?_activeShape,
                          if (_pendingAngle.isNotEmpty)
                            AnnotationShape(
                              tool: AnnotationTool.angle,
                              points: _pendingAngle,
                              colorHex: _colorHex,
                            ),
                        ],
                        settings: _settings,
                        mmPerPixel: _mmPerPixel,
                        overlayBuilder: (context, box) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: _isDrawing ? (d) => _onTap(d.localPosition, box) : null,
                          onPanStart: _isDrawing ? (d) => _onPanStart(d.localPosition, box) : null,
                          onPanUpdate: _isDrawing ? (d) => _onPanUpdate(d.localPosition, box) : null,
                          onPanEnd: _isDrawing ? (_) => _onPanEnd() : null,
                        ),
                      ),
                    ),
            ),
          ),
          _buildPanel(context),
        ],
      ),
    );
  }

  /// Zoom and drawing can't share the same gestures: an InteractiveViewer
  /// wins the gesture arena and every stroke would be swallowed as a pan. So
  /// the viewer is only live in "Move" mode; while a tool is selected the
  /// image keeps the exact same transform through a plain [Transform], which
  /// means the dentist can zoom in first and then draw precisely.
  Widget _zoomable(Widget child) {
    if (_isDrawing) {
      return ClipRect(
        child: Transform(
          transform: _zoom.value,
          child: child,
        ),
      );
    }
    return InteractiveViewer(
      transformationController: _zoom,
      minScale: 1,
      maxScale: 8,
      child: child,
    );
  }

  Widget _buildPanel(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _hint,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _showAdjust = !_showAdjust),
                  icon: Icon(
                    _showAdjust ? Icons.brush_outlined : Icons.tune,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: Text(
                    _showAdjust ? 'Tools' : 'Image',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            if (_showAdjust) _buildAdjustPanel() else _buildToolPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wrapped, not scrolled: on a phone a scrolling row hides half the
        // tools, and a tool you can't see is a tool you don't use.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 2,
          children: [
            _tool(_Mode.pan, Icons.pan_tool_outlined, 'Move'),
            _tool(_Mode.freehand, Icons.edit, 'Draw'),
            _tool(_Mode.line, Icons.show_chart, 'Line'),
            _tool(_Mode.measure, Icons.straighten, 'Measure'),
            _tool(_Mode.angle, Icons.architecture, 'Angle'),
            _tool(_Mode.text, Icons.label_outline, 'Label'),
            _tool(_Mode.implant, Icons.hardware_outlined, 'Implant'),
            _tool(_Mode.canal, Icons.timeline, 'Canal'),
            _tool(_Mode.calibrate, Icons.square_foot, 'Scale'),
          ],
        ),
        if (_mode == _Mode.implant) _buildImplantSizes(),
        const SizedBox(height: 6),
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
                    backgroundColor: Color(
                      int.parse('FF${hex.replaceFirst('#', '')}', radix: 16),
                    ),
                    child: _colorHex == hex
                        ? const Icon(Icons.check, size: 14, color: Colors.black)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildImplantSizes() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Text('Ø', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButton<double>(
              value: _implantDiameter,
              isExpanded: true,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: [
                for (final d in _kImplantDiameters)
                  DropdownMenuItem(value: d, child: Text('${d.toStringAsFixed(1)} mm')),
              ],
              onChanged: (value) => setState(() => _implantDiameter = value ?? _implantDiameter),
            ),
          ),
          const SizedBox(width: 12),
          const Text('L', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButton<double>(
              value: _implantLength,
              isExpanded: true,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: [
                for (final l in _kImplantLengths)
                  DropdownMenuItem(value: l, child: Text('${l.toStringAsFixed(1)} mm')),
              ],
              onChanged: (value) => setState(() => _implantLength = value ?? _implantLength),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _slider(
          icon: Icons.brightness_6_outlined,
          value: _settings.brightness,
          onChanged: (v) => setState(() => _settings = _settings.copyWith(brightness: v)),
        ),
        _slider(
          icon: Icons.contrast,
          value: _settings.contrast,
          onChanged: (v) => setState(() => _settings = _settings.copyWith(contrast: v)),
        ),
        Row(
          children: [
            const Text(
              'Negative',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            Switch(
              value: _settings.inverted,
              onChanged: (v) => setState(() => _settings = _settings.copyWith(inverted: v)),
            ),
            const Spacer(),
            TextButton(
              onPressed: _settings.isDefault
                  ? null
                  : () => setState(() => _settings = ImageViewSettings.none),
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _slider({
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        Expanded(
          child: Slider(
            value: value,
            min: -1,
            max: 1,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _tool(_Mode mode, IconData icon, String label) {
    final selected = _mode == mode;
    final color = selected ? Theme.of(context).colorScheme.primary : Colors.white70;
    return InkWell(
      onTap: () => setState(() {
        _mode = mode;
        _pendingAngle = [];
      }),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
