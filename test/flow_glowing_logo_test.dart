import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_glowing_logo.dart';

Widget scene({bool reduced = false, bool enabled = true}) => MaterialApp(home: MediaQuery(data: MediaQueryData(disableAnimations: reduced), child: TickerMode(enabled: enabled, child: const Scaffold(body: Center(child: FlowGlowingLogo())))));

void main() {
  testWidgets('moving logo keeps its layout and releases its ticker', (tester) async {
    await tester.pumpWidget(scene());
    final before = tester.getRect(find.byType(FlowGlowingLogo));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getRect(find.byType(FlowGlowingLogo)), before);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('logo stops for reduced motion and hidden screens', (tester) async {
    await tester.pumpWidget(scene(reduced: true));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene()); await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(scene(enabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
