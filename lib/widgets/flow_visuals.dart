import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/flow_theme.dart';
import 'ripple_advisor_visuals.dart';

/// Decorative motion never intercepts input or adds accessibility announcements.
class FlowLiquidCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const FlowLiquidCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  State<FlowLiquidCard> createState() => _FlowLiquidCardState();
}

class _FlowLiquidCardState extends State<FlowLiquidCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: FlowTheme.blue.withValues(alpha: .16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _LiquidPainter(_motion)),
              ),
            ),
            Theme(
              data: theme.copyWith(
                textTheme: theme.textTheme.apply(
                  bodyColor: Colors.white,
                  displayColor: Colors.white,
                ),
              ),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: Padding(padding: widget.padding, child: widget.child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final Animation<double> motion;
  _LiquidPainter(this.motion) : super(repaint: motion);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0089D5), Color(0xFF0649DA), Color(0xFF007AA3)],
        ).createShader(rect),
    );
    final phase = motion.value * math.pi * 2;
    // Light waves and bubbles occupy the bottom/right edge, away from labels.
    for (var layer = 0; layer < 2; layer++) {
      final y = size.height * .86 + layer * 13;
      final path = Path()..moveTo(0, y);
      path.cubicTo(
        size.width * .38,
        y + 30 * math.sin(phase),
        size.width * .68,
        y - 40,
        size.width,
        y - 18,
      );
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: .02),
              FlowTheme.aqua.withValues(alpha: .35),
            ],
          ).createShader(rect),
      );
    }
    for (var i = 0; i < 5; i++) {
      final radius = 7.0 + (i % 3) * 8;
      final x = size.width * (.83 + .07 * math.sin(i * 2.4));
      final y = size.height * (.14 + i * .16) + math.sin(phase + i) * 8;
      final bubble = Rect.fromCircle(center: Offset(x, y), radius: radius);
      canvas.drawCircle(
        bubble.center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.45, -.55),
            colors: [
              Colors.white.withValues(alpha: .55),
              Colors.white.withValues(alpha: .05),
              const Color(0xFF70EDFF).withValues(alpha: .25),
            ],
            stops: const [0, .4, 1],
          ).createShader(bubble),
      );
      canvas.drawCircle(
        bubble.center,
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: bubble.center + Offset(-radius * .3, -radius * .4),
          width: radius * .5,
          height: radius * .23,
        ),
        Paint()..color = Colors.white.withValues(alpha: .7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) =>
      motion != oldDelegate.motion;
}

class FlowOrb extends StatelessWidget {
  final double size;
  const FlowOrb({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-.4, -.5),
        colors: [
          Colors.white,
          Color(0xFF69F4FF),
          Color(0xFF00B4D6),
          Color(0xFF075BEE),
        ],
        stops: [0, .25, .65, 1],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .7)),
      boxShadow: [
        BoxShadow(
          color: FlowTheme.aqua.withValues(alpha: .3),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
  );
}

class FinnyButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const FinnyButton({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) =>
      RippleBubbleButton(onPressed: onPressed);
}

class FlowActions extends StatelessWidget {
  final VoidCallback? onAdvisor;
  final Widget? primary;
  const FlowActions({super.key, this.onAdvisor, this.primary});
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 12,
    children: [
      if (onAdvisor != null) FinnyButton(onPressed: onAdvisor),
      if (primary != null) primary!,
    ],
  );
}

/// Custom categories use a stable palette derived from their stored ID/name.
class FlowCategoryIcon extends StatelessWidget {
  final String category;
  const FlowCategoryIcon({super.key, required this.category});
  static (IconData, Color) styleFor(String category) {
    final name = category.toLowerCase();
    return switch (name) {
      String n when n.contains('food') || n.contains('lunch') => (
        Icons.restaurant_rounded,
        const Color(0xFFE87500),
      ),
      String n when n.contains('transport') || n.contains('bus') => (
        Icons.directions_bus_rounded,
        const Color(0xFF087CD6),
      ),
      String n when n.contains('shop') => (
        Icons.shopping_bag_rounded,
        const Color(0xFF8949DE),
      ),
      String n when n.contains('health') => (
        Icons.favorite_rounded,
        const Color(0xFFD94665),
      ),
      String n when n.contains('educat') => (
        Icons.school_rounded,
        const Color(0xFF008D83),
      ),
      String n when n.contains('water') => (
        Icons.water_drop_rounded,
        const Color(0xFF00A7B6),
      ),
      String n when n.contains('electric') => (
        Icons.bolt_rounded,
        const Color(0xFFE9A019),
      ),
      String n when n.contains('internet') => (
        Icons.wifi_rounded,
        const Color(0xFF008FD9),
      ),
      String n when n.contains('laptop') => (
        Icons.laptop_mac_rounded,
        const Color(0xFF8949DE),
      ),
      String n when n.contains('emergency') => (
        Icons.shield_outlined,
        const Color(0xFF008D83),
      ),
      String n when n.contains('home') => (
        Icons.home_rounded,
        const Color(0xFFBA631E),
      ),
      String n when n.contains('entertain') => (
        Icons.movie_rounded,
        const Color(0xFFAE449B),
      ),
      _ => (
        Icons.category_rounded,
        [
          const Color(0xFF087CD6),
          const Color(0xFF8949DE),
          const Color(0xFF008D83),
        ][category.codeUnits.fold<int>(0, (a, b) => a + b) % 3],
      ),
    };
  }

  static Color colorFor(String category) => styleFor(category).$2;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = styleFor(category);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: .7), color],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Colors.white, size: 23),
    );
  }
}

class FlowWelcomeBackground extends StatelessWidget {
  const FlowWelcomeBackground({super.key});
  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _WelcomeWaterPainter()));
}

class _WelcomeWaterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF2FAFF), Color(0xFFE1F7FF)],
        ).createShader(rect),
    );
    for (var i = 0; i < 3; i++) {
      final y = size.height * (.85 + i * .04);
      final wave = Path()
        ..moveTo(0, y)
        ..cubicTo(
          size.width * .35,
          y - 65,
          size.width * .65,
          y + 70,
          size.width,
          y - 15,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        wave,
        Paint()
          ..shader = LinearGradient(
            colors: [
              FlowTheme.aqua.withValues(alpha: .09 + i * .04),
              FlowTheme.blue.withValues(alpha: .05 + i * .025),
            ],
          ).createShader(rect),
      );
    }
    for (final bubble in [
      (x: .89, y: .12, r: 20.0),
      (x: .95, y: .20, r: 9.0),
      (x: .12, y: .91, r: 18.0),
      (x: .86, y: .78, r: 12.0),
    ]) {
      final center = Offset(size.width * bubble.x, size.height * bubble.y);
      final bounds = Rect.fromCircle(center: center, radius: bubble.r);
      canvas.drawCircle(
        center,
        bubble.r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-.4, -.5),
            colors: [Colors.white, Color(0xFFCBF5FF), Color(0xFF82DCEB)],
          ).createShader(bounds),
      );
      canvas.drawCircle(
        center,
        bubble.r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WelcomeWaterPainter oldDelegate) => false;
}

class FlowBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  const FlowBottomNav({
    super.key,
    required this.selectedIndex,
    this.onSelected,
  });
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.format_list_bulleted_rounded),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.track_changes_rounded),
              label: 'Plan',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    ),
  );
}

/// Align actions with the centered mobile column on wider browser windows.
class FlowFabLocation extends FloatingActionButtonLocation {
  const FlowFabLocation();
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final original = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    final columnWidth = math.min(480.0, geometry.scaffoldSize.width);
    final right = (geometry.scaffoldSize.width + columnWidth) / 2;
    return Offset(
      right - geometry.floatingActionButtonSize.width - 16,
      original.dy,
    );
  }
}
