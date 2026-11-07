import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_auth_water_background.dart';

Widget scene({
  bool reduced = false,
  bool enabled = true,
  VoidCallback? onTap,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: TickerMode(
      enabled: enabled,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: const ColoredBox(color: Colors.white),
            ),
            const Positioned.fill(child: FlowAuthWaterBackground()),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('paint-only water animation leaves controls tappable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(scene(onTap: () => taps++));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 12));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion and hidden screens stop scheduling frames', (
    tester,
  ) async {
    await tester.pumpWidget(scene(reduced: true));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(scene(enabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
