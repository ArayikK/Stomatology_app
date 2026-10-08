import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// What a drawn shape means. Older saved annotations only ever used the
/// first three, so anything unknown decodes back to [freehand].
enum AnnotationTool {
  /// Free drawing, any number of points.
  freehand,

  /// A plain straight line, two points.
  line,

  /// A straight line that prints its length - in millimetres when the image
  /// is calibrated, in pixels when it isn't.
  measurement,

  /// Three points (arm, vertex, arm) printing the angle between them.
  angle,

  /// An arrow with a short caption at its tail.
  text,

  /// An implant template drawn to scale: points are the platform (top) and
  /// the apex (tip), with the diameter taken from [AnnotationShape.implantWidthMm].
  implant,

  /// The mandibular canal, drawn as a polyline. Implant templates report how
  /// far their apex sits from it.
  canal,
}

/// One drawn shape on an image, in coordinates normalized to 0..1 of the
/// image's natural (pixel) width/height - so it renders correctly
/// regardless of what size the image happens to be displayed at.
class AnnotationShape {
  const AnnotationShape({
    required this.tool,
    required this.points,
    required this.colorHex,
    this.text,
    this.implantWidthMm,
    this.implantLengthMm,
  });

  final AnnotationTool tool;
  final List<Offset> points;
  final String colorHex;

  /// The caption of a [AnnotationTool.text] arrow.
  final String? text;

  /// Diameter and length of an [AnnotationTool.implant] template, in mm.
  final double? implantWidthMm;
  final double? implantLengthMm;

  Color get color => Color(int.parse('FF${colorHex.replaceFirst('#', '')}', radix: 16));

  AnnotationShape copyWith({
    List<Offset>? points,
    String? text,
    double? implantWidthMm,
    double? implantLengthMm,
  }) {
    return AnnotationShape(
      tool: tool,
      points: points ?? this.points,
      colorHex: colorHex,
      text: text ?? this.text,
      implantWidthMm: implantWidthMm ?? this.implantWidthMm,
      implantLengthMm: implantLengthMm ?? this.implantLengthMm,
    );
  }

  AnnotationShape withAddedPoint(Offset point) => copyWith(points: [...points, point]);

  AnnotationShape withEndPoint(Offset point) => copyWith(points: [points.first, point]);

  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    'points': [
      for (final p in points) [p.dx, p.dy],
    ],
    'color': colorHex,
    if (text != null) 'text': text,
    if (implantWidthMm != null) 'implantWidthMm': implantWidthMm,
    if (implantLengthMm != null) 'implantLengthMm': implantLengthMm,
  };

  factory AnnotationShape.fromJson(Map<String, dynamic> json) {
    return AnnotationShape(
      tool: AnnotationTool.values.firstWhere(
        (t) => t.name == json['tool'],
        orElse: () => AnnotationTool.freehand,
      ),
      points: [
        for (final p in (json['points'] as List))
          Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
      colorHex: json['color'] as String? ?? '#FF3B30',
      text: json['text'] as String?,
      implantWidthMm: (json['implantWidthMm'] as num?)?.toDouble(),
      implantLengthMm: (json['implantLengthMm'] as num?)?.toDouble(),
    );
  }
}

List<AnnotationShape> decodeAnnotations(String? json) {
  if (json == null || json.trim().isEmpty) return const [];
  final decoded = jsonDecode(json) as List;
  return [for (final item in decoded) AnnotationShape.fromJson(item as Map<String, dynamic>)];
}

String encodeAnnotations(List<AnnotationShape> shapes) {
  return jsonEncode([for (final shape in shapes) shape.toJson()]);
}

/// Converts between normalized (0..1) coordinates and real-world distances.
/// [mmPerPixel] is null when the image has no known scale, in which case
/// distances are reported in pixels.
class ImageScale {
  const ImageScale({required this.imageSize, this.mmPerPixel});

  final Size imageSize;
  final double? mmPerPixel;

  bool get isCalibrated => mmPerPixel != null && mmPerPixel! > 0;

  /// Distance between two normalized points, in image pixels.
  double pixelDistance(Offset a, Offset b) {
    final dx = (b.dx - a.dx) * imageSize.width;
    final dy = (b.dy - a.dy) * imageSize.height;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Distance between two normalized points in millimetres, or null when the
  /// image isn't calibrated.
  double? millimetres(Offset a, Offset b) {
    if (!isCalibrated) return null;
    return pixelDistance(a, b) * mmPerPixel!;
  }

  /// The label a measurement prints: "12.4 mm" when calibrated, "83 px"
  /// otherwise.
  String describeDistance(Offset a, Offset b) {
    final mm = millimetres(a, b);
    if (mm == null) return '${pixelDistance(a, b).round()} px';
    return '${mm.toStringAsFixed(1)} mm';
  }

  /// Normalized length of a segment that is [mm] long in the real world,
  /// measured along [direction]. Used to draw implant templates to scale.
  double normalizedLengthForMm(double mm, Offset direction) {
    final spacing = mmPerPixel ?? 1;
    final pixels = mm / spacing;
    // Normalized space is anisotropic when the image isn't square, so the
    // conversion depends on which way the segment points.
    final len = direction.distance;
    if (len == 0) return pixels / imageSize.height;
    final ux = direction.dx / len;
    final uy = direction.dy / len;
    final px = ux * imageSize.width;
    final py = uy * imageSize.height;
    final perNormalized = math.sqrt(px * px + py * py);
    return pixels / perNormalized;
  }
}

/// The angle in degrees at [vertex] between the two arms, or null if the
/// points are degenerate. Coordinates are normalized, so they are scaled by
/// [imageSize] first - otherwise a non-square image reports a wrong angle.
double? angleDegrees(Offset a, Offset vertex, Offset b, Size imageSize) {
  Offset toPixels(Offset o) => Offset(o.dx * imageSize.width, o.dy * imageSize.height);
  final v1 = toPixels(a) - toPixels(vertex);
  final v2 = toPixels(b) - toPixels(vertex);
  if (v1.distance == 0 || v2.distance == 0) return null;
  final cos = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
  return math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Shortest distance from a normalized [point] to a polyline, in the same
/// units [scale] measures in. Used to tell how close an implant apex is to
/// the mandibular canal.
double? distanceToPolyline(Offset point, List<Offset> polyline, ImageScale scale) {
  if (polyline.length < 2) return null;
  double? best;
  for (var i = 0; i < polyline.length - 1; i++) {
    final closest = _closestPointOnSegment(point, polyline[i], polyline[i + 1], scale.imageSize);
    final d = scale.millimetres(point, closest) ?? scale.pixelDistance(point, closest);
    if (best == null || d < best) best = d;
  }
  return best;
}

Offset _closestPointOnSegment(Offset p, Offset a, Offset b, Size imageSize) {
  Offset toPixels(Offset o) => Offset(o.dx * imageSize.width, o.dy * imageSize.height);
  final pa = toPixels(a);
  final pb = toPixels(b);
  final pp = toPixels(p);
  final ab = pb - pa;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return a;
  var t = ((pp.dx - pa.dx) * ab.dx + (pp.dy - pa.dy) * ab.dy) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
}
