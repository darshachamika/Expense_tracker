import 'package:flutter/material.dart';
import '../theme/flow_theme.dart';
import 'flow_visuals.dart';

/// Runs once per app launch. The destination mounts immediately beneath it.
class FlowLaunch extends StatefulWidget {
  final Widget child;
  const FlowLaunch({super.key, required this.child});
  @override
  State<FlowLaunch> createState() => _FlowLaunchState();
}
class _FlowLaunchState extends State<FlowLaunch> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_started) {
      _controller.forward();
    }
    _started = true;
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = _controller.value;
      final reveal = ((t - .72) / .28).clamp(0.0, 1.0).toDouble();
      return Stack(fit: StackFit.expand, children: [
        ExcludeSemantics(excluding: t < 1, child: IgnorePointer(ignoring: t < 1, child: child!)),
        if (t < 1) Positioned.fill(child: Opacity(opacity: 1 - reveal, child: const ColoredBox(color: FlowTheme.background))),
        if (t < 1) Positioned.fill(child: IgnorePointer(child: Opacity(opacity: 1 - reveal,
          child: Material(color: Colors.transparent, child: Container(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF042A77), FlowTheme.blue, Color(0xFF00BCD4)])),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Transform.scale(scale: .25 + Curves.easeOutBack.transform((t / .7).clamp(0.0, 1.0).toDouble()), child: const FlowOrb(size: 96)),
              const SizedBox(height: 28),
              const Text('Flow', style: TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: -1.8)),
              const SizedBox(height: 10),
              const Text('Money, in a better flow.', style: TextStyle(color: Colors.white, fontSize: 16)),
            ])),
          )),
        ))),
      ]);
    },
  );
}
