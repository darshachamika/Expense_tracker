import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flow_motion_lifecycle.dart';

/// Keeps Flow's blue/cyan orb while light moves across its glassy surface.
class FlowGlowingLogo extends StatefulWidget {
  final double size;
  const FlowGlowingLogo({super.key, this.size = 76});

  @override
  State<FlowGlowingLogo> createState() => _FlowGlowingLogoState();
}

class _FlowGlowingLogoState extends State<FlowGlowingLogo>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _light = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _active = true, _reduced = false, _enabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _active = flowMotionIsVisible(state);
  }

  void _sync() {
    if (_active && !_reduced && _enabled) {
      if (!_light.isAnimating) _light.repeat();
    } else {
      _light.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _enabled = TickerMode.of(context);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = flowMotionIsVisible(state);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Flow logo',
    image: true,
    child: IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _FlowLogoLight(_light)),
        ),
      ),
    ),
  );
}

class _FlowLogoLight extends CustomPainter {
  final Animation<double> light;
  _FlowLogoLight(this.light) : super(repaint: light);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * .46;
    final t = light.value * 2 * math.pi;
    final pulse = .5 + .5 * math.sin(t);
    final sphere = Rect.fromCircle(center: center, radius: r);

    // Soft colored bloom, with no flashing or changes to the logo silhouette.
    canvas.drawCircle(
      center,
      r * 1.12,
      Paint()
        ..color = const Color(0xFF00D9F5).withValues(alpha: .16 + pulse * .15)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          r * (.22 + pulse * .09),
        ),
    );
    canvas.drawCircle(
      center + Offset(0, r * .12),
      r * .94,
      Paint()
        ..color = const Color(0xFF006AFF).withValues(alpha: .14)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .24),
    );

    final highlight = Alignment(
      -.40 + math.sin(t) * .25,
      -.45 + math.cos(t) * .18,
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: highlight,
          radius: 1.25,
          colors: const [
            Color(0xFFA7FCFF),
            Color(0xFF0DDFE9),
            Color(0xFF008DDD),
            Color(0xFF075BEE),
            Color(0xFF0648D8),
          ],
          stops: const [0, .18, .43, .68, 1],
        ).createShader(sphere),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    // A curved reflective band travels over the surface like the reference light.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t);
    final sweep = Rect.fromLTWH(-r, -r * .9, r * 2, r * .9);
    canvas.drawOval(
      sweep,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .19),
            const Color(0xFF6FF8FF).withValues(alpha: .03),
          ],
          stops: const [0, .55, 1],
        ).createShader(sweep),
    );
    canvas.restore();

    final glint = center + Offset(highlight.x * r * .72, highlight.y * r * .72);
    final specular = Rect.fromCircle(center: glint, radius: r * .36);
    canvas.drawCircle(
      glint,
      r * .36,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: .86),
            Colors.white.withValues(alpha: .20),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, .30, 1],
        ).createShader(specular),
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      r - .3,
      Paint()
        ..shader = SweepGradient(
          transform: GradientRotation(t),
          colors: [
            const Color(0xFFCCFFFF).withValues(alpha: .6),
            const Color(0xFF0773F8).withValues(alpha: .1),
            Colors.white.withValues(alpha: .72),
            const Color(0xFFCCFFFF).withValues(alpha: .6),
          ],
        ).createShader(sphere)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .85,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowLogoLight oldDelegate) =>
      oldDelegate.light != light;
}
