import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// First-launch welcome page with the "Take the tour" call to action.
/// Motion here is a one-shot entrance only - nothing repeats, so it costs no
/// battery once shown and never stalls `pumpAndSettle` in tests.
class IntroScreen extends StatefulWidget {
  const IntroScreen({
    super.key,
    required this.onTakeTour,
    required this.onSkip,
  });

  final VoidCallback onTakeTour;
  final VoidCallback onSkip;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroColors {
  /// The artwork's own dark teal, shown for the instant before it decodes.
  static const Color background = Color(0xFF003B37);
  static const Color titleHighlight = Color(0xFFC4FAF1);
  static const Color buttonText = Color(0xFF0B4A43);
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const String _backgroundAsset =
      'assets/images/welcome_background.jpg';

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  bool _leaving = false;

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Staggered fade + rise for the element starting at [start] (0-1).
  Widget _reveal(double start, Widget child) {
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        start,
        math.min(start + 0.45, 1),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }

  void _choose(VoidCallback action) {
    if (_leaving) return;
    _leaving = true;
    action();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final textTheme = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status-bar icons over the dark artwork.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _IntroColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Anchored right so the tooth stays in view on any screen shape.
            const Image(
              image: AssetImage(_backgroundAsset),
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              excludeFromSemantics: true,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: size.height * 0.1),
                    _reveal(0, const _Headline()),
                    const SizedBox(height: 18),
                    _reveal(
                      0.12,
                      Text(
                        'Modern tools for\nmodern dentistry.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 20,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _reveal(
                      0.45,
                      _PillButton(
                        label: 'Take the tour',
                        textStyle: textTheme.labelLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        onPressed: () => _choose(widget.onTakeTour),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _reveal(
                      0.55,
                      Center(
                        child: TextButton(
                          onPressed: () => _choose(widget.onSkip),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(
                              alpha: 0.8,
                            ),
                            textStyle: textTheme.labelLarge?.copyWith(
                              fontSize: 15,
                            ),
                          ),
                          child: const Text('Skip for now'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome to',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w300,
            height: 1.1,
          ),
        ),
        // "Stom" fades from white into a pale teal, like light on enamel.
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, _IntroColors.titleHighlight],
          ).createShader(bounds),
          child: const Text(
            'Stom',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w800,
              height: 1.05,
              letterSpacing: -1,
            ),
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onPressed,
    this.textStyle,
  });

  final String label;
  final VoidCallback onPressed;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _IntroColors.buttonText,
          shape: const StadiumBorder(),
          elevation: 0,
          textStyle: textStyle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward, size: 22),
          ],
        ),
      ),
    );
  }
}
