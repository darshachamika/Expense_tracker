import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_video_launch.dart';

class Playback extends FlowIntroPlayback {
  bool done = false, broken = false, disposed = false;
  @override
  bool get ready => true;
  @override
  bool get completed => done;
  @override
  bool get failed => broken;
  @override
  Size get size => const Size(360, 640);
  @override
  Future<void> prepare() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Widget video() => const Text('Intro video');
  void finish() {
    done = true;
    notifyListeners();
  }

  void fail() {
    broken = true;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  testWidgets('plays intro first without Skip and reveals home on completion', (
    tester,
  ) async {
    final playback = Playback();
    await tester.pumpWidget(
      MaterialApp(
        home: FlowVideoLaunch(
          createPlayback: () => playback,
          child: const Scaffold(body: Text('Home destination')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Intro video'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    playback.finish();
    await tester.pumpAndSettle();
    expect(find.text('Intro video'), findsNothing);
    expect(find.text('Home destination'), findsOneWidget);
    expect(playback.disposed, isTrue);
  });
  testWidgets('a video decoding error still reveals the destination', (
    tester,
  ) async {
    final playback = Playback();
    await tester.pumpWidget(
      MaterialApp(
        home: FlowVideoLaunch(
          createPlayback: () => playback,
          child: const Scaffold(body: Text('Home destination')),
        ),
      ),
    );
    await tester.pump();
    playback.fail();
    await tester.pumpAndSettle();
    expect(find.text('Intro video'), findsNothing);
    expect(find.text('Home destination'), findsOneWidget);
  });
  testWidgets('intro fills a wide viewport using cover scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = Playback();
    await tester.pumpWidget(
      MaterialApp(
        home: FlowVideoLaunch(
          createPlayback: () => playback,
          child: const Scaffold(body: Text('Home destination')),
        ),
      ),
    );
    await tester.pump();
    final box = tester.widget<FittedBox>(find.byType(FittedBox));
    expect(box.fit, BoxFit.cover);
    expect(tester.getSize(find.byType(FittedBox)), const Size(1200, 600));
    playback.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
