import 'dart:convert';

import 'package:flutter/widgets.dart';

/// How one image should be displayed: the brightness/contrast the dentist
/// dialled in, and whether it is shown inverted ("negative"). Saved per
/// image, so a dark x-ray stays readable the next time it is opened. The
/// image file itself is never modified.
@immutable
class ImageViewSettings {
  const ImageViewSettings({
    this.brightness = 0,
    this.contrast = 0,
    this.inverted = false,
  });

  /// -1 (much darker) .. 0 (untouched) .. 1 (much brighter).
  final double brightness;

  /// -1 (flat) .. 0 (untouched) .. 1 (hard).
  final double contrast;

  final bool inverted;

  static const ImageViewSettings none = ImageViewSettings();

  bool get isDefault => brightness == 0 && contrast == 0 && !inverted;

  ImageViewSettings copyWith({double? brightness, double? contrast, bool? inverted}) {
    return ImageViewSettings(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      inverted: inverted ?? this.inverted,
    );
  }

  Map<String, dynamic> toJson() => {
    'brightness': brightness,
    'contrast': contrast,
    'inverted': inverted,
  };

  factory ImageViewSettings.fromJson(Map<String, dynamic> json) {
    return ImageViewSettings(
      brightness: ((json['brightness'] as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0),
      contrast: ((json['contrast'] as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0),
      inverted: json['inverted'] as bool? ?? false,
    );
  }

  static ImageViewSettings decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return none;
    try {
      return ImageViewSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return none;
    }
  }

  String encode() => jsonEncode(toJson());

  /// The 4x5 colour matrix that applies these settings, ready for
  /// [ColorFilter.matrix]. Contrast pivots around mid-grey so the image
  /// doesn't drift darker as contrast rises; inversion is folded into the
  /// same matrix so there is only ever one filter in the tree.
  List<double> colorMatrix() {
    // contrast: 0 -> 1.0x, +1 -> 3.0x, -1 -> 0.25x
    final c = contrast >= 0 ? 1 + contrast * 2 : 1 + contrast * 0.75;
    // brightness: +-1 shifts by a full +-255/2 of the range
    final b = brightness * 128;
    final sign = inverted ? -1.0 : 1.0;
    final scale = c * sign;
    // Pivot on mid-grey (127.5, the true middle of 0..255), so contrast
    // doesn't drift the image darker and inversion maps 0 to exactly 255.
    final offset = 127.5 - 127.5 * scale + b;
    return <double>[
      scale, 0, 0, 0, offset,
      0, scale, 0, 0, offset,
      0, 0, scale, 0, offset,
      0, 0, 0, 1, 0,
    ];
  }
}
