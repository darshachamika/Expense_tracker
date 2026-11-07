import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flow_motion_lifecycle.dart';

/// Paint-only motion: the login form is neither rebuilt nor hit-tested by water.
class FlowAuthWaterBackground extends StatefulWidget {
  const FlowAuthWaterBackground({super.key});

  @override
  State<FlowAuthWaterBackground> createState() =>
      _FlowAuthWaterBackgroundState();
}

class _FlowAuthWaterBackgroundState extends State<FlowAuthWaterBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  bool _active = true;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _active = flowMotionIsVisible(state);
  }

  void _syncMotion() {
    if (_active && !_reduceMotion && _tickerEnabled) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.of(context);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = flowMotionIsVisible(state);
    _syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: ClipRect(child: CustomPaint(painter: _WaterPainter(_motion))),
      ),
    ),
  );
}

class _Bubble {
  final double x, radius, phase, drift;
  final int laps;
  const _Bubble(this.x, this.radius, this.phase, this.drift, this.laps);
}

class _WaterPainter extends CustomPainter {
  final Animation<double> motion;
  _WaterPainter(this.motion) : super(repaint: motion);

  // Fixed seeds avoid jumping or regenerating particles when the form rebuilds.
  static const _bubbles = [
    _Bubble(.06, 20, .03, 8, 1),
    _Bubble(.14, 7, .30, 12, 2),
    _Bubble(.08, 12, .58, 6, 1),
    _Bubble(.20, 5, .80, 10, 2),
    _Bubble(.91, 24, .18, 8, 1),
    _Bubble(.96, 8, .49, 7, 2),
    _Bubble(.85, 13, .72, 12, 1),
    _Bubble(.94, 5, .95, 6, 2),
    _Bubble(.30, 5, .14, 9, 1),
    _Bubble(.73, 6, .43, 10, 2),
    _Bubble(.05, 9, .90, 6, 2),
    _Bubble(.88, 10, .05, 9, 2),
    _Bubble(.17, 16, .46, 8, 1),
    _Bubble(.79, 7, .87, 7, 2),
    _Bubble(.40, 4, .67, 10, 1),
    _Bubble(.65, 5, .29, 10, 1),
    _Bubble(.97, 14, .65, 5, 1),
    _Bubble(.03, 5, .39, 5, 2),
    _Bubble(.24, 6, .98, 8, 1),
    _Bubble(.83, 5, .34, 9, 2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFEFF), Color(0xFFF0FBFF), Color(0xFFDDF7FF)],
        ).createShader(rect),
    );
    final t = motion.value * math.pi * 2;

    // A soft aqua wash keeps the middle clear and the water luminous below.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(.8, 1.1),
          radius: 1.1,
          colors: [Color(0x4D43DAF5), Color(0x0000CBEA)],
        ).createShader(rect),
    );

    for (var i = 0; i < 3; i++) {
      final y = size.height * (.86 + i * .045);
      final shift = math.sin(t + i * 1.7) * 12;
      final path = Path()..moveTo(-20, y + shift);
      path.cubicTo(
        size.width * .28,
        y - 52 + shift,
        size.width * .62,
        y + 65 - shift,
        size.width + 20,
        y - 14 + shift,
      );
      path.lineTo(size.width + 20, size.height + 20);
      path.lineTo(-20, size.height + 20);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF30DFF1).withValues(alpha: .11 + i * .035),
              const Color(0xFF0788F7).withValues(alpha: .07 + i * .035),
            ],
          ).createShader(rect),
      );
      final crest = Path()..moveTo(-20, y + shift);
      crest.cubicTo(
        size.width * .28,
        y - 52 + shift,
        size.width * .62,
        y + 65 - shift,
        size.width + 20,
        y - 14 + shift,
      );
      canvas.drawPath(
        crest,
        Paint()
          ..color = Colors.white.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    final scale = (size.width / 430).clamp(.8, 1.35).toDouble();
    for (var i = 0; i < _bubbles.length; i++) {
      final bubble = _bubbles[i];
      final r = bubble.radius * scale;
      final travel = (motion.value * bubble.laps + bubble.phase) % 1;
      final y = size.height + r * 2 - travel * (size.height + r * 4);
      final x =
          size.width * bubble.x +
          math.sin(t * bubble.laps + i * 1.9) * bubble.drift;
      // Smaller/fainter central particles sit behind opaque form surfaces.
      final opacity = bubble.x > .24 && bubble.x < .78 ? .48 : .9;
      _drawBubble(canvas, Offset(x, y), r, opacity);
    }
  }

  void _drawBubble(Canvas canvas, Offset center, double r, double opacity) {
    final bounds = Rect.fromCircle(center: center, radius: r);
    // A nearly clear interior gives the impression of water, not a solid ball.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.5),
          colors: [
            Colors.white.withValues(alpha: .68 * opacity),
            const Color(0xFF8AF4FF).withValues(alpha: .09 * opacity),
            const Color(0xFF2DCCE9).withValues(alpha: .22 * opacity),
            Colors.white.withValues(alpha: .55 * opacity),
          ],
          stops: const [0, .32, .82, 1],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      center,
      r - .4,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: .9 * opacity),
            const Color(0xFF40CCF1).withValues(alpha: .7 * opacity),
            const Color(0xFFA6B8FF).withValues(alpha: .45 * opacity),
            Colors.white.withValues(alpha: .95 * opacity),
          ],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r > 12 ? 1.4 : .8,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * .84),
      math.pi * 1.08,
      math.pi * .48,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: .92 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r > 12 ? 2.1 : 1,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(-r * .31, -r * .42),
        width: r * .35,
        height: r * .16,
      ),
      Paint()..color = Colors.white.withValues(alpha: .78 * opacity),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * .83),
      .15,
      .8,
      false,
      Paint()
        ..color = const Color(0xFF89EEFF).withValues(alpha: .62 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _WaterPainter oldDelegate) =>
      oldDelegate.motion != motion;
}
