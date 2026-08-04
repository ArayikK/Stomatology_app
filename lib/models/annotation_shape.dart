import 'dart:convert';
import 'dart:ui';

enum AnnotationTool { freehand, line, measurement }

/// One drawn shape on an image, in coordinates normalized to 0..1 of the
/// image's natural (pixel) width/height - so it renders correctly
/// regardless of what size the image happens to be displayed at.
class AnnotationShape {
  const AnnotationShape({
    required this.tool,
    required this.points,
    required this.colorHex,
  });

  final AnnotationTool tool;
  final List<Offset> points;
  final String colorHex;

  Color get color => Color(int.parse('FF${colorHex.replaceFirst('#', '')}', radix: 16));

  AnnotationShape withAddedPoint(Offset point) {
    return AnnotationShape(tool: tool, points: [...points, point], colorHex: colorHex);
  }

  AnnotationShape withEndPoint(Offset point) {
    return AnnotationShape(tool: tool, points: [points.first, point], colorHex: colorHex);
  }

  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    'points': [
      for (final p in points) [p.dx, p.dy],
    ],
    'color': colorHex,
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
