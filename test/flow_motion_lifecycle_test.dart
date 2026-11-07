import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_app_water.dart';
import 'package:expense_tracker/widgets/flow_auth_water_background.dart';
import 'package:expense_tracker/widgets/flow_glowing_logo.dart';

void main() {
  testWidgets('all water and glow keep ticking when visible but unfocused', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    FlowWaterMotion.introVisible.value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FlowAppWater(
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: const [
                FlowAuthWaterBackground(),
                Center(child: FlowGlowingLogo()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 3);
    // Several complete bubble/glow cycles must keep scheduling frames.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 29));
      expect(tester.binding.transientCallbackCount, 3);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
