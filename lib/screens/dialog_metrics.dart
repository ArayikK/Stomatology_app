import 'package:flutter/material.dart';

/// The width a form dialog's content should take.
///
/// An [AlertDialog] sizes itself to its widest child, so a dialog full of
/// chips, fields and dropdowns ends up with each row a slightly different
/// width. Giving the content one explicit width instead keeps every row
/// aligned to the same edges. [LayoutBuilder] can't be used for this: the
/// dialog measures its content with intrinsic sizing, which a LayoutBuilder
/// doesn't support.
///
/// The value is the screen width minus the dialog's own insets (40 each side)
/// and content padding (24 each side), capped so it doesn't sprawl on a
/// tablet or desktop window.
double kDialogContentWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return (screenWidth - 128).clamp(220.0, 400.0);
}
