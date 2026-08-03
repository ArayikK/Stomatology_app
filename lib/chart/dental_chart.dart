import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import 'tooth_paths.dart';
import 'tooth_state.dart';

/// Renders the 32-tooth chart from [tooth_paths.dart] and hit-tests taps
/// back to a universal tooth number (1-32). All state is hoisted to the
/// caller via [state] / [onToothTap] - this widget owns no tooth data itself.
class DentalChart extends StatelessWidget {
  const DentalChart({super.key, required this.state, this.onToothTap});

  final Map<int, ToothState> state;
  final ValueChanged<int>? onToothTap;

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final callback = onToothTap;
            if (callback == null) return;
            final tooth = _hitTest(geometry, size, details.localPosition);
            if (tooth != null) callback(tooth);
          },
          child: CustomPaint(
            size: size,
            painter: _DentalChartPainter(geometry: geometry, state: state),
          ),
        );
      },
    );
  }

  static int? _hitTest(_ToothGeometry geometry, Size size, Offset localPosition) {
    final transform = _ChartTransform(size);
    final point = transform.toViewBox(localPosition);
    for (var number = 32; number >= 1; number--) {
      final path = geometry.hitPaths[number];
      if (path != null && path.contains(point)) {
        return number;
      }
    }
    return null;
  }
}

class _ChartTransform {
  factory _ChartTransform(Size canvasSize) {
    final scale = math.min(
      canvasSize.width / kViewBoxWidth,
      canvasSize.height / kViewBoxHeight,
    );
    final dx = (canvasSize.width - kViewBoxWidth * scale) / 2;
    final dy = (canvasSize.height - kViewBoxHeight * scale) / 2;
    return _ChartTransform._(scale, Offset(dx, dy));
  }

  const _ChartTransform._(this.scale, this.offset);

  final double scale;
  final Offset offset;

  Offset toViewBox(Offset canvasPoint) => (canvasPoint - offset) / scale;
}

class _ColoredPath {
  const _ColoredPath(this.color, this.path);

  final Color color;
  final Path path;
}

class _ToothGeometry {
  const _ToothGeometry({
    required this.base,
    required this.teeth,
    required this.hitPaths,
  });

  final List<_ColoredPath> base;
  final Map<int, List<_ColoredPath>> teeth;

  /// One combined path per tooth (union of all its sub-shapes), used both
  /// for the highlight-overlay fill and for tap hit-testing.
  final Map<int, Path> hitPaths;
}

Color _colorFromHex(String hex) {
  final value = hex.replaceFirst('#', '');
  return Color(int.parse('FF$value', radix: 16));
}

_ToothGeometry? _cachedGeometry;

/// Path parsing is done once per process and cached - not on every build/paint.
_ToothGeometry get _geometry {
  final cached = _cachedGeometry;
  if (cached != null) return cached;

  final base = [
    for (final entry in kBase)
      _ColoredPath(_colorFromHex(entry.key), parseSvgPathData(entry.value)),
  ];

  final teeth = <int, List<_ColoredPath>>{};
  final hitPaths = <int, Path>{};
  for (final toothEntry in kTeeth.entries) {
    final colored = [
      for (final entry in toothEntry.value)
        _ColoredPath(_colorFromHex(entry.key), parseSvgPathData(entry.value)),
    ];
    teeth[toothEntry.key] = colored;

    final combined = Path();
    for (final c in colored) {
      combined.addPath(c.path, Offset.zero);
    }
    hitPaths[toothEntry.key] = combined;
  }

  final geometry = _ToothGeometry(base: base, teeth: teeth, hitPaths: hitPaths);
  _cachedGeometry = geometry;
  return geometry;
}

class _DentalChartPainter extends CustomPainter {
  _DentalChartPainter({required this.geometry, required this.state});

  final _ToothGeometry geometry;
  final Map<int, ToothState> state;

  static const _highlightColor = Color(0xFF2F6FED);

  @override
  void paint(Canvas canvas, Size size) {
    final transform = _ChartTransform(size);
    final fillPaint = Paint()..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(transform.offset.dx, transform.offset.dy);
    canvas.scale(transform.scale);

    for (final colored in geometry.base) {
      canvas.drawPath(colored.path, fillPaint..color = colored.color);
    }

    for (var number = 1; number <= 32; number++) {
      final colored = geometry.teeth[number];
      if (colored == null) continue;
      final override = state[number]?.colorOverride;
      if (override != null) {
        final hitPath = geometry.hitPaths[number]!;
        canvas.drawPath(hitPath, fillPaint..color = override);
      } else {
        for (final c in colored) {
          canvas.drawPath(c.path, fillPaint..color = c.color);
        }
      }
    }

    for (var number = 1; number <= 32; number++) {
      if (state[number]?.hasHistory != true) continue;
      final hitPath = geometry.hitPaths[number];
      if (hitPath == null) continue;
      canvas.drawPath(
        hitPath,
        fillPaint..color = _highlightColor.withValues(alpha: 0.55),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DentalChartPainter oldDelegate) {
    return oldDelegate.state != state;
  }
}
