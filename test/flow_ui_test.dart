import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/theme/flow_theme.dart';
import 'package:expense_tracker/widgets/flow_launch.dart';
import 'package:expense_tracker/widgets/flow_visuals.dart';

Widget surface(Widget child, {bool reducedMotion = false, double scale = 1}) =>
    MaterialApp(
      theme: FlowTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(scale),
          ),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('launch reveals its mounted destination once and allows taps', (
    tester,
  ) async {
    var taps = 0;
    var mounts = 0;
    await tester.pumpWidget(
      surface(
        FlowLaunch(
          child: _MountProbe(
            onMount: () => mounts++,
            child: Scaffold(
              body: TextButton(
                onPressed: () => taps++,
                child: const Text('Destination'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Flow'), findsOneWidget);
    await tester.tap(find.text('Destination'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pump(const Duration(milliseconds: 1700));
    expect(find.text('Flow'), findsNothing);
    expect(mounts, 1);
    await tester.tap(find.text('Destination'));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Flow'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips launch and stops decorative tickers', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        const FlowLaunch(
          child: Scaffold(body: FlowLiquidCard(child: Text('Saved amount'))),
        ),
        reducedMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Flow'), findsNothing);
    expect(find.text('Saved amount'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('liquid card preserves taps and disposes its running ticker', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      surface(
        Scaffold(
          body: FlowLiquidCard(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 25));
    await tester.tap(find.text('Open'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets(
      'actions wrap and remain usable at width $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var asks = 0;
        await tester.pumpWidget(
          surface(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  FlowLiquidCard(
                    child: Text(
                      'Rs. 999,999.99',
                      style: TextStyle(fontSize: 28),
                    ),
                  ),
                  SizedBox(height: 20),
                  FlowCategoryIcon(category: 'Food'),
                ],
              ),
              floatingActionButton: FlowActions(
                onAdvisor: () => asks++,
                primary: FloatingActionButton.extended(
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                  label: const Text('New goal'),
                ),
              ),
            ),
            reducedMotion: true,
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ripple'));
        expect(asks, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _MountProbe extends StatefulWidget {
  final VoidCallback onMount;
  final Widget child;
  const _MountProbe({required this.onMount, required this.child});
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
