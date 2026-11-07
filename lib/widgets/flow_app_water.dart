import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flow_motion_lifecycle.dart';

/// Shared calm water only. Navigation never starts a bubble burst.
abstract final class FlowWaterMotion {
  static final introVisible = ValueNotifier<bool>(false);
  static void setIntroVisible(bool visible) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      introVisible.value = visible;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

class FlowAppWater extends StatefulWidget {
  final Widget child;
  const FlowAppWater({super.key, required this.child});
  @override
  State<FlowAppWater> createState() => _FlowAppWaterState();
}

class _FlowAppWaterState extends State<FlowAppWater>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );
  bool _active = true, _reduced = false, _enabled = true;
  bool get _visible => !FlowWaterMotion.introVisible.value;
  bool get _canMove => _visible && _active && !_reduced && _enabled;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _active = flowMotionIsVisible(state);
    WidgetsBinding.instance.addObserver(this);
    FlowWaterMotion.introVisible.addListener(_introChanged);
  }

  void _introChanged() {
    if (!mounted) return;
    _sync();
    setState(() {});
  }

  void _sync() {
    if (_canMove) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      _ambient.stop();
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
    FlowWaterMotion.introVisible.removeListener(_introChanged);
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_visible)
        Positioned.fill(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ClipRect(
                  child: CustomPaint(
                    painter: _AppWaterPainter(
                      _ambient,
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _AppWaterPainter extends CustomPainter {
  final Animation<double> ambient;
  final bool dark;
  _AppWaterPainter(this.ambient, {required this.dark})
    : super(repaint: ambient);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = (size.width / 430).clamp(.8, 1.35).toDouble();
    for (var i = 0; i < 12; i++) {
      final r = (4 + (i % 4) * 3.0) * scale;
      final progress = (ambient.value + i * .137) % 1;
      final x =
          size.width *
              (i.isEven ? .025 + (i % 3) * .018 : .975 - (i % 3) * .018) +
          math.sin(ambient.value * math.pi * 2 + i) * 6;
      final y = size.height + 2 * r - progress * (size.height + 4 * r);
      _bubble(canvas, Offset(x, y), r, dark ? .32 : .23);
    }
  }

  void _bubble(Canvas canvas, Offset c, double r, double alpha) {
    final bounds = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.4, -.5),
          colors: [
            Colors.white.withValues(alpha: alpha * .72),
            const Color(0xFF84F2FF).withValues(alpha: alpha * .07),
            const Color(0xFF0ACFEF).withValues(alpha: alpha * .30),
          ],
          stops: const [0, .38, 1],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            const Color(0xFF10BDE9).withValues(alpha: alpha),
            const Color(0xFF7CBBFF).withValues(alpha: alpha * .6),
            Colors.white.withValues(alpha: alpha),
          ],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * .82),
      math.pi * 1.08,
      math.pi * .40,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r > 12 ? 1.8 : 1,
    );
  }

  @override
  bool shouldRepaint(covariant _AppWaterPainter oldDelegate) =>
      oldDelegate.ambient != ambient || oldDelegate.dark != dark;
}
