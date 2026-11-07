import 'dart:ui';

import 'package:flutter/material.dart';

/// Thin outlined message icon with a water ripple, drawn without a new package.
class RippleMark extends StatelessWidget {
  final double size;
  const RippleMark({super.key, this.size = 26});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RippleMarkPainter(
        Theme.of(context).colorScheme.brightness == Brightness.dark
            ? const Color(0xFF8AEFFF)
            : const Color(0xFF006CBB),
      ),
    ),
  );
}

class _RippleMarkPainter extends CustomPainter {
  final Color color;
  const _RippleMarkPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(5, 18)
      ..lineTo(3, 21)
      ..lineTo(3.8, 15.8)
      ..cubicTo(-.5, 7.8, 6, 1, 13, 2.2)
      ..cubicTo(24, 2.3, 25, 17, 14.5, 20)
      ..cubicTo(11, 21, 7, 20, 5, 18);
    canvas.drawPath(path, paint);
    final wave = Path()
      ..moveTo(7, 11)
      ..cubicTo(9, 8, 11, 14, 13, 11)
      ..cubicTo(15, 8, 17, 14, 19, 11);
    canvas.drawPath(wave, paint);
    canvas.drawCircle(const Offset(11.5, 6.5), .7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RippleMarkPainter old) => old.color != color;
}

class RippleBubbleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const RippleBubbleButton({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Ask Ripple, your Flow assistant',
      button: true,
      child: Tooltip(
        message: 'Ask Ripple',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00CFE8).withValues(alpha: .20),
                blurRadius: 16,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
              child: Material(
                color: dark ? const Color(0xDD12364E) : const Color(0xDDE4FBFF),
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: const Color(0xFF61DDF5),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const RippleMark(),
                        const SizedBox(width: 9),
                        Text(
                          'Ripple',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: dark
                                ? const Color(0xFFE4FCFF)
                                : const Color(0xFF103758),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A finite entrance, so glowing answers never create a permanent extra ticker.
class RippleReveal extends StatelessWidget {
  final Widget child;
  const RippleReveal({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 14),
          child: Transform.scale(
            scale: .96 + value * .04,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      ),
    );
  }
}

class RippleAnswerCard extends StatelessWidget {
  final String question, answer;
  const RippleAnswerCard({
    super.key,
    required this.question,
    required this.answer,
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF11273F) : const Color(0xFFF8FEFF);
    return RippleReveal(
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF76EFFF), Color(0xFF159AF4), Color(0xFFB6A5FF)],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00CFE8)
                  .withValues(alpha: dark ? .21 : .12),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.5),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  RippleMark(size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ripple’s explanation',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                question,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(height: 24),
              Semantics(
                liveRegion: true,
                child: SelectableText(
                  answer,
                  style: const TextStyle(height: 1.55),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Based on the recorded data used when you asked. No records were changed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
