import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_video_launch.dart';
import 'package:expense_tracker/widgets/flow_startup_gate.dart';

class Intro extends FlowIntroPlayback {
  @override
  bool get ready => true;
  @override
  bool get failed => false;
  @override
  bool completed = false;
  @override
  Size get size => const Size(360, 640);
  @override
  Future<void> prepare() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Widget video() => const Text('Video');
  void finish() {
    completed = true;
    notifyListeners();
  }
}

void main() {
  testWidgets('initialization starts once only after intro completion', (
    tester,
  ) async {
    var starts = 0;
    final pending = Completer<void>();
    final intro = Intro();
    await tester.pumpWidget(
      MaterialApp(
        home: FlowVideoLaunch(
          createPlayback: () => intro,
          child: FlowStartupGate(
            initialize: () {
              starts++;
              return pending.future;
            },
            destination: const Scaffold(body: Text('Home')),
            errorBuilder: (_, error) => const Text('Setup failed'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(starts, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    intro.finish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(starts, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('initialization errors show the recovery screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FlowStartupGate(
          initialize: () async => throw StateError('Offline'),
          destination: const Text('Home'),
          errorBuilder: (_, error) => const Text('Setup failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Setup failed'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
