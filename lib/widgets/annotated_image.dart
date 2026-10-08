import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation_shape.dart';
import '../models/image_view_settings.dart';

/// Draws the saved shapes over an image. Coordinates are normalized 0..1 of
/// the image's natural size, so the same shapes render correctly on a
/// thumbnail, on a full screen view and in a printed report.
///
/// [scale] carries the image's real-world scale: measurements print in
/// millimetres when it is calibrated and in pixels when it is not.
class AnnotationPainter extends CustomPainter {
  const AnnotationPainter({
    required this.shapes,
    required this.scale,
    this.strokeWidth = 3,
    this.fontSize = 12,
  });

  final List<AnnotationShape> shapes;
  final ImageScale scale;
  final double strokeWidth;
  final double fontSize;

  Size get imageSize => scale.imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    Offset toPixel(Offset n) => Offset(n.dx * size.width, n.dy * size.height);

    // Canal polylines are needed while drawing implants, to report how close
    // the implant apex comes to the nerve.
    final canals = [
      for (final shape in shapes)
        if (shape.tool == AnnotationTool.canal && shape.points.length >= 2) shape.points,
    ];

    for (final shape in shapes) {
      if (shape.points.isEmpty) continue;
      final paint = Paint()
        ..color = shape.color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      switch (shape.tool) {
        case AnnotationTool.freehand:
          if (shape.points.length < 2) continue;
          canvas.drawPath(_pathThrough(shape.points, toPixel), paint);

        case AnnotationTool.line:
          if (shape.points.length < 2) continue;
          canvas.drawLine(toPixel(shape.points.first), toPixel(shape.points.last), paint);

        case AnnotationTool.measurement:
          if (shape.points.length < 2) continue;
          final a = shape.points.first;
          final b = shape.points.last;
          final start = toPixel(a);
          final end = toPixel(b);
          canvas.drawLine(start, end, paint);
          _drawEndCaps(canvas, start, end, paint);
          _drawLabel(
            canvas,
            scale.describeDistance(a, b),
            Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2),
            shape.color,
          );

        case AnnotationTool.angle:
          if (shape.points.length < 3) {
            if (shape.points.length == 2) {
              canvas.drawLine(toPixel(shape.points[0]), toPixel(shape.points[1]), paint);
            }
            continue;
          }
          final arm1 = shape.points[0];
          final vertex = shape.points[1];
          final arm2 = shape.points[2];
          canvas.drawLine(toPixel(vertex), toPixel(arm1), paint);
          canvas.drawLine(toPixel(vertex), toPixel(arm2), paint);
          final degrees = angleDegrees(arm1, vertex, arm2, imageSize);
          if (degrees != null) {
            _drawLabel(
              canvas,
              '${degrees.toStringAsFixed(0)}°',
              toPixel(vertex) + const Offset(0, -14),
              shape.color,
            );
          }

        case AnnotationTool.text:
          if (shape.points.length < 2) continue;
          final tail = toPixel(shape.points.first);
          final head = toPixel(shape.points.last);
          canvas.drawLine(tail, head, paint);
          _drawArrowHead(canvas, tail, head, paint);
          final label = (shape.text ?? '').trim();
          if (label.isNotEmpty) _drawLabel(canvas, label, tail, shape.color);

        case AnnotationTool.canal:
          if (shape.points.length < 2) continue;
          final canalPaint = Paint()
            ..color = shape.color
            ..strokeWidth = strokeWidth + 1
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          canvas.drawPath(_pathThrough(shape.points, toPixel), canalPaint);
          _drawLabel(canvas, 'canal', toPixel(shape.points.first), shape.color);

        case AnnotationTool.implant:
          if (shape.points.length < 2) continue;
          _drawImplant(canvas, shape, toPixel, canals);
      }
    }
  }

  Path _pathThrough(List<Offset> points, Offset Function(Offset) toPixel) {
    final first = toPixel(points.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final point in points.skip(1)) {
      final p = toPixel(point);
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  /// The implant is drawn as a rounded body with a flat platform at the top
  /// and thread ticks down the side, scaled from its real millimetre size.
  void _drawImplant(
    Canvas canvas,
    AnnotationShape shape,
    Offset Function(Offset) toPixel,
    List<List<Offset>> canals,
  ) {
    final platform = shape.points.first;
    final apex = shape.points.last;
    final platformPx = toPixel(platform);
    final apexPx = toPixel(apex);
    final axis = apexPx - platformPx;
    if (axis.distance < 1) return;

    final lengthMm = shape.implantLengthMm ?? 10;
    final widthMm = shape.implantWidthMm ?? 3.5;
    final halfWidthPx = axis.distance * (widthMm / lengthMm) / 2;

    final direction = axis / axis.distance;
    final normal = Offset(-direction.dy, direction.dx);

    final body = Path()
      ..moveTo(
        platformPx.dx + normal.dx * halfWidthPx,
        platformPx.dy + normal.dy * halfWidthPx,
      )
      ..lineTo(
        apexPx.dx + normal.dx * halfWidthPx * 0.45,
        apexPx.dy + normal.dy * halfWidthPx * 0.45,
      )
      ..lineTo(
        apexPx.dx - normal.dx * halfWidthPx * 0.45,
        apexPx.dy - normal.dy * halfWidthPx * 0.45,
      )
      ..lineTo(
        platformPx.dx - normal.dx * halfWidthPx,
        platformPx.dy - normal.dy * halfWidthPx,
      )
      ..close();

    canvas.drawPath(
      body,
      Paint()
        ..color = shape.color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = shape.color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );

    // Thread ticks: purely to read as an implant rather than a rectangle.
    final threadPaint = Paint()
      ..color = shape.color.withValues(alpha: 0.8)
      ..strokeWidth = strokeWidth * 0.5;
    const threads = 6;
    for (var i = 1; i < threads; i++) {
      final t = i / threads;
      final centre = platformPx + axis * t;
      final half = halfWidthPx * (1 - 0.55 * t);
      canvas.drawLine(
        centre + normal * half,
        centre - normal * half,
        threadPaint,
      );
    }

    final label = StringBuffer(
      'Ø${widthMm.toStringAsFixed(1)} × ${lengthMm.toStringAsFixed(0)} mm',
    );
    double? nearest;
    for (final canal in canals) {
      final distance = distanceToPolyline(apex, canal, scale);
      if (distance != null && (nearest == null || distance < nearest)) nearest = distance;
    }
    if (nearest != null) {
      label.write(
        scale.isCalibrated
            ? '\nto canal: ${nearest.toStringAsFixed(1)} mm'
            : '\nto canal: ${nearest.round()} px',
      );
    }
    _drawLabel(canvas, label.toString(), platformPx - Offset(0, fontSize * 1.6), shape.color);
  }

  void _drawEndCaps(Canvas canvas, Offset start, Offset end, Paint paint) {
    final axis = end - start;
    if (axis.distance < 1) return;
    final normal = Offset(-axis.dy, axis.dx) / axis.distance * 6;
    canvas.drawLine(start - normal, start + normal, paint);
    canvas.drawLine(end - normal, end + normal, paint);
  }

  void _drawArrowHead(Canvas canvas, Offset tail, Offset head, Paint paint) {
    final axis = head - tail;
    if (axis.distance < 1) return;
    final direction = axis / axis.distance;
    final normal = Offset(-direction.dy, direction.dx);
    const size = 10.0;
    final left = head - direction * size + normal * size * 0.5;
    final right = head - direction * size - normal * size * 0.5;
    canvas.drawLine(head, left, paint);
    canvas.drawLine(head, right, paint);
  }

  void _drawLabel(Canvas canvas, String text, Offset at, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}

/// An image with its brightness/contrast/inversion applied and its saved
/// annotations drawn on top, laid out at the image's own aspect ratio.
class AnnotatedImageView extends StatelessWidget {
  const AnnotatedImageView({
    super.key,
    required this.file,
    required this.imageSize,
    this.shapes = const [],
    this.settings = ImageViewSettings.none,
    this.mmPerPixel,
    this.overlayBuilder,
  });

  final File file;
  final Size imageSize;
  final List<AnnotationShape> shapes;
  final ImageViewSettings settings;
  final double? mmPerPixel;

  /// Extra layer drawn above the annotations, given the laid-out box size -
  /// used by the editor for its in-progress shape and handles.
  final Widget Function(BuildContext context, Size box)? overlayBuilder;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: imageSize.width / imageSize.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.matrix(settings.colorMatrix()),
                  child: Image.file(file, fit: BoxFit.fill, gaplessPlayback: true),
                ),
                CustomPaint(
                  size: box,
                  painter: AnnotationPainter(
                    shapes: shapes,
                    scale: ImageScale(imageSize: imageSize, mmPerPixel: mmPerPixel),
                  ),
                ),
                if (overlayBuilder != null) overlayBuilder!(context, box),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Reads an image file's natural pixel size, needed before any annotation
/// can be placed. Returns null if the file can't be decoded.
Future<Size?> readImageSize(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}
