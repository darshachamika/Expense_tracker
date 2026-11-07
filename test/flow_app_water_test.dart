import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_app_water.dart';

Widget app({bool reduced = false}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: FlowAppWater(child: child!),
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          child: const Text('Open detail'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  Scaffold(appBar: AppBar(title: const Text('Detail page'))),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    FlowWaterMotion.introVisible.value = false;
  });

  testWidgets('route changes retain only the continuous ambient ticker', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.tap(find.text('Open detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Detail page'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Open detail'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion stays tappable without scheduling frames', (
    tester,
  ) async {
    await tester.pumpWidget(app(reduced: true));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.text('Detail page'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('intro suppression ends and ambient resumes', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    FlowWaterMotion.introVisible.value = true;
    await tester.pumpWidget(app());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    FlowWaterMotion.setIntroVisible(false);
    await tester.pump();
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
