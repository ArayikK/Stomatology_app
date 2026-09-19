import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// One coach mark: the widget to cut out of the scrim and what to say about it.
class TourStep {
  const TourStep({
    required this.target,
    required this.title,
    required this.body,
    this.pad = 7,
  });

  /// Key sitting on the real widget being explained.
  final GlobalKey target;
  final String title;
  final String body;

  /// How far the highlight extends beyond the target. Small for dense
  /// targets, 10-12 for cards and panels.
  final double pad;
}

enum TourOutcome { finished, skipped }

/// Shows [steps] over the current screen as a spotlight tour and resolves
/// once the user finishes or skips it. Steps whose target isn't on screen
/// (e.g. an allergy banner for a patient without allergies) are dropped up
/// front, so the step counter only counts what will actually be shown.
Future<TourOutcome> showSpotlightTour(
  BuildContext context,
  List<TourStep> steps,
) async {
  final visible = [
    for (final step in steps)
      if (step.target.currentContext != null) step,
  ];
  if (visible.isEmpty) return TourOutcome.finished;
  final outcome = await Navigator.of(context).push<TourOutcome>(
    PageRouteBuilder(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => SpotlightTour(steps: visible),
    ),
  );
  return outcome ?? TourOutcome.skipped;
}

/// Colors for the tour. The overlay stays dark in both light and dark app
/// themes (the cutout must be the only lit thing on screen), so it uses the
/// dark variant of the app's own seed palette.
class _TourColors {
  factory _TourColors() {
    final dark = ColorScheme.fromSeed(
      seedColor: kStomSeedColor,
      brightness: Brightness.dark,
    );
    return _TourColors._(
      accent: dark.primary,
      tipBackground: dark.surfaceContainerHigh,
      title: dark.onSurface,
      body: dark.onSurfaceVariant,
      track: dark.outlineVariant,
      buttonText: dark.onPrimary,
      skipBackground: dark.surfaceContainerLowest,
      skipBorder: dark.outlineVariant,
    );
  }

  const _TourColors._({
    required this.accent,
    required this.tipBackground,
    required this.title,
    required this.body,
    required this.track,
    required this.buttonText,
    required this.skipBackground,
    required this.skipBorder,
  });

  /// Near-black with a hint of teal.
  static const Color scrim = Color(0xFF020A09);
  static const double scrimAlpha = 0.74;

  final Color accent;
  final Color tipBackground;
  final Color title;
  final Color body;
  final Color track;
  final Color buttonText;
  final Color skipBackground;
  final Color skipBorder;
}

class SpotlightTour extends StatefulWidget {
  const SpotlightTour({super.key, required this.steps});

  final List<TourStep> steps;

  @override
  State<SpotlightTour> createState() => _SpotlightTourState();
}

class _SpotlightTourState extends State<SpotlightTour>
    with TickerProviderStateMixin {
  static const Duration _stepFade = Duration(milliseconds: 320);
  static const Duration _exitFade = Duration(milliseconds: 400);
  static const double _gap = 16;
  static const double _tipMargin = 14;
  static const double _maxTipWidth = 440;
  static const double _screenClamp = 9;

  final GlobalKey _tipKey = GlobalKey();
  final _TourColors _colors = _TourColors();

  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: _stepFade,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _fadeCtrl,
    curve: Curves.easeOutCubic,
  );
  late final AnimationController _overlayCtrl = AnimationController(
    vsync: this,
    duration: _stepFade,
    reverseDuration: _exitFade,
  );

  int _step = 0;
  bool _leaving = false;
  bool _closing = false;
  Rect? _spot;
  double? _tipH;

  TourStep get _current => widget.steps[_step];
  bool get _isLast => _step == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _overlayCtrl.forward();
    _revealCurrentStep();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _overlayCtrl.dispose();
    super.dispose();
  }

  /// Scrolls the target into view while the spotlight fades in. The measure
  /// pass runs on every animation frame, so the hole follows the scroll.
  void _revealCurrentStep() {
    final targetContext = _current.target.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.4,
        duration: _stepFade,
        curve: Curves.easeOutCubic,
      );
    }
    _fadeCtrl.forward();
  }

  void _measure() {
    if (!mounted) return;
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize) return;

    // The tooltip's real height replaces the first-frame estimate.
    final tipBox = _tipKey.currentContext?.findRenderObject();
    if (tipBox is RenderBox && tipBox.hasSize && _tipH != tipBox.size.height) {
      setState(() => _tipH = tipBox.size.height);
    }

    final targetContext = _current.target.currentContext;
    if (targetContext == null) return;
    final box = targetContext.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;

    // The target lives in the screen below this route, so it isn't a render
    // ancestor of ours - convert through global coordinates instead.
    final origin =
        box.localToGlobal(Offset.zero) - self.localToGlobal(Offset.zero);
    final raw = (origin & box.size).inflate(_current.pad);

    // Inflate first, then clamp, so an edge target keeps even padding.
    final w = self.size.width;
    final h = self.size.height;
    final rect = Rect.fromLTRB(
      raw.left.clamp(_screenClamp, w - _screenClamp),
      raw.top.clamp(_screenClamp, h - _screenClamp),
      raw.right.clamp(_screenClamp, w - _screenClamp),
      raw.bottom.clamp(_screenClamp, h - _screenClamp),
    );
    // Runs every frame: only rebuild when something actually moved.
    if (_spot != rect) setState(() => _spot = rect);
  }

  void _next() {
    if (_leaving) return;
    if (_isLast) {
      _close(TourOutcome.finished);
      return;
    }
    setState(() => _leaving = true);
    _fadeCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _step++;
        _leaving = false;
        _spot = null;
        _tipH = null;
      });
      _revealCurrentStep();
    });
  }

  void _close(TourOutcome outcome) {
    if (_closing) return;
    _closing = true;
    setState(() => _leaving = true);
    _overlayCtrl.reverse().then((_) {
      if (mounted) Navigator.of(context).pop(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<TourOutcome>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(TourOutcome.skipped);
      },
      child: FadeTransition(
        opacity: _overlayCtrl,
        child: AnimatedBuilder(
          animation: _fade,
          builder: (context, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return _buildFrame(context);
          },
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final safeTop = media.padding.top;
    final t = _fade.value;
    final spot = _spot;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Swallows taps so the screen underneath can't be used mid-tour.
          const Positioned.fill(child: AbsorbPointer(child: SizedBox.expand())),
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                spot: spot,
                opacity: t,
                accent: _colors.accent,
              ),
            ),
          ),
          if (spot != null) _buildTooltip(size, safeTop, spot, t),
          Positioned(
            top: safeTop + 8,
            right: 14,
            child: _SkipChip(
              colors: _colors,
              onTap: () => _close(TourOutcome.skipped),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTooltip(Size size, double safeTop, Rect spot, double t) {
    final tipWidth = math.min(size.width - _tipMargin * 2, _maxTipWidth);
    final tipLeft = ((spot.left + spot.right) / 2 - tipWidth / 2).clamp(
      _tipMargin,
      size.width - _tipMargin - tipWidth,
    );

    // First frame only: estimate the height from the text length. From the
    // second frame on, the measured height is used.
    final charsPerLine = math.max(1, ((tipWidth - 32) / 6.6).floor());
    final bodyLines =
        (_current.body.length / charsPerLine).ceil() +
        (_current.title.length > charsPerLine ? 1 : 0);
    final tipH = _tipH ?? (132.0 + bodyLines * 20.0);

    final minTop = safeTop + 44;
    final maxTop = size.height - tipH - 12;

    double tipTop;
    bool arrowUp;
    final below = spot.bottom + _gap;
    if (below <= maxTop) {
      tipTop = below;
      arrowUp = true;
    } else {
      tipTop = spot.top - tipH - _gap;
      arrowUp = false;
    }
    // Too tall for either side: keep it on screen, even over the spotlight.
    tipTop = maxTop < minTop ? minTop : tipTop.clamp(minTop, maxTop);

    final arrowX = ((spot.left + spot.right) / 2 - tipLeft - 7).clamp(
      14.0,
      tipWidth - 28,
    );

    final arrow = Positioned(
      left: arrowX,
      top: arrowUp ? -6 : null,
      bottom: arrowUp ? null : -6,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(width: 14, height: 14, color: _colors.tipBackground),
      ),
    );
    final card = _TooltipCard(
      key: _tipKey,
      colors: _colors,
      stepLabel: 'STEP ${_step + 1} OF ${widget.steps.length}',
      title: _current.title,
      body: _current.body,
      progress: (_step + 1) / widget.steps.length,
      buttonLabel: _isLast ? 'Finish' : 'Next',
      onPressed: _next,
    );

    return Positioned(
      left: tipLeft,
      top: tipTop,
      width: tipWidth,
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          // Slides away from its arrow, as if emerging from the target.
          offset: Offset(0, (1 - t) * (arrowUp ? 10 : -10)),
          child: Stack(
            clipBehavior: Clip.none,
            // The card must paint over the arrow's inner half.
            children: arrowUp ? [arrow, card] : [card, arrow],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.spot,
    required this.opacity,
    required this.accent,
  });

  static const double _radius = 14;

  final Rect? spot;
  final double opacity;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final o = opacity.clamp(0.0, 1.0);
    final full = Offset.zero & size;
    final scrimPaint = Paint()
      ..color = _TourColors.scrim.withValues(alpha: _TourColors.scrimAlpha);

    final spot = this.spot;
    if (spot == null) {
      canvas.drawRect(full, scrimPaint);
      return;
    }

    final rr = RRect.fromRectAndRadius(spot, const Radius.circular(_radius));

    // The backdrop stays at a constant alpha; only the hole fades in and
    // out between steps, so the screen never flashes bright.
    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, scrimPaint);
    canvas.drawRRect(rr, Paint()..blendMode = BlendMode.clear);
    if (o < 1) {
      canvas.drawRRect(
        rr,
        Paint()
          ..color = _TourColors.scrim.withValues(
            alpha: _TourColors.scrimAlpha * (1 - o),
          ),
      );
    }
    canvas.restore();

    // Glow drawn only outside the shape, so it never hazes the target.
    canvas.drawRRect(
      rr,
      Paint()
        ..color = accent.withValues(alpha: 0.55 * o)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 7),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = accent.withValues(alpha: o)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.spot != spot || old.opacity != opacity || old.accent != accent;
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    super.key,
    required this.colors,
    required this.stepLabel,
    required this.title,
    required this.body,
    required this.progress,
    required this.buttonLabel,
    required this.onPressed,
  });

  final _TourColors colors;
  final String stepLabel;
  final String title;
  final String body;
  final double progress;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.tipBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stepLabel,
            style: TextStyle(
              color: colors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: colors.title,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(color: colors.body, fontSize: 13, height: 1.55),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 4,
                    color: colors.track,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      heightFactor: 1,
                      child: ColoredBox(color: colors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.buttonText,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(buttonLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkipChip extends StatelessWidget {
  const _SkipChip({required this.colors, required this.onTap});

  final _TourColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Skip tour',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.skipBackground,
            border: Border.all(color: colors.skipBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Skip tour',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
