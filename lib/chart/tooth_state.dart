import 'package:flutter/material.dart';

/// Per-tooth render/behaviour state, hoisted to whatever screen owns the chart.
class ToothState {
  const ToothState({required this.number, this.hasHistory = false, this.colorOverride});

  final int number;

  /// True when the tooth has at least one note or x-ray on file -> drawn
  /// with the blue highlight overlay.
  final bool hasHistory;

  /// When set, the tooth is drawn as a single solid fill in this color
  /// instead of its natural multi-shade artwork (e.g. to mark it missing).
  final Color? colorOverride;

  ToothState copyWith({bool? hasHistory, Color? colorOverride}) {
    return ToothState(
      number: number,
      hasHistory: hasHistory ?? this.hasHistory,
      colorOverride: colorOverride ?? this.colorOverride,
    );
  }
}
