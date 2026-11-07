import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_video_launch.dart';

class FakeIntro extends FlowIntroPlayback {
  @override
  bool ready = false;
  @override
  bool completed = false;
  @override
  bool failed = false;
  bool disposed = false, reject = false;
  int plays = 0;
  Completer<void>? pending;
  @override
  Size get size => const Size(1080, 1920);
  @override
  Future<void> prepare() async {
    if (pending != null) await pending!.future;
    if (disposed) return;
    if (reject) throw StateError('Decoder failed');
    ready = true;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> pause() async {}
  @override
  Widget video() =>
      const ColoredBox(key: ValueKey('test-video'), color: Colors.blue);
  void end() {
    completed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class MountProbe extends StatefulWidget {
  final VoidCallback onMount, onTap;
  const MountProbe({super.key, required this.onMount, required this.onTap});
  @override
  State<MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(onPressed: widget.onTap, child: const Text('Destination')),
  );
}

Widget launch(
  FakeIntro player, {
  bool reduced = false,
  Duration timeout = const Duration(seconds: 12),
  VoidCallback? onMount,
  VoidCallback? onTap,
}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: FlowVideoLaunch(
        createPlayback: () => player,
        timeout: timeout,
        child: MountProbe(onMount: onMount ?? () {}, onTap: onTap ?? () {}),
      ),
    ),
  ),
);

void main() {
  testWidgets('only intro runs; destination mounts once after completion', (
    tester,
  ) async {
    final player = FakeIntro();
    var mounts = 0, taps = 0;
    await tester.pumpWidget(
      launch(player, onMount: () => mounts++, onTap: () => taps++),
    );
    await tester.pump();
    expect(player.plays, 1);
    expect(mounts, 0);
    expect(find.text('Destination'), findsNothing);
    expect(find.byKey(const ValueKey('test-video')), findsOneWidget);
    player.end();
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(player.disposed, isTrue);
    expect(find.byKey(const ValueKey('test-video')), findsNothing);
    await tester.tap(find.text('Destination'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('no Skip and no destination before playback completes', (
    tester,
  ) async {
    final player = FakeIntro();
    await tester.pumpWidget(launch(player));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Destination'), findsNothing);
    expect(player.disposed, isFalse);
    player.end();
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
  });
  testWidgets('reduced motion opens destination without preparing video', (
    tester,
  ) async {
    final player = FakeIntro();
    await tester.pumpWidget(launch(player, reduced: true));
    await tester.pumpAndSettle();
    expect(player.plays, 0);
    expect(player.ready, isFalse);
    expect(find.text('Destination'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
  testWidgets('decoder failure opens destination and releases resources', (
    tester,
  ) async {
    final player = FakeIntro()..reject = true;
    await tester.pumpWidget(launch(player));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(find.text('Destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('stalled initialization times out and ignores late completion', (
    tester,
  ) async {
    final pending = Completer<void>();
    final player = FakeIntro()..pending = pending;
    await tester.pumpWidget(
      launch(player, timeout: const Duration(milliseconds: 500)),
    );
    expect(find.text('Destination'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pump();
    expect(player.disposed, isTrue);
    expect(player.plays, 0);
    expect(find.text('Destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'disposing during preparation prevents late playback or page mounting',
    (tester) async {
      final pending = Completer<void>();
      final player = FakeIntro()..pending = pending;
      var mounts = 0;
      await tester.pumpWidget(launch(player, onMount: () => mounts++));
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pump();
      expect(player.disposed, isTrue);
      expect(player.plays, 0);
      expect(mounts, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
