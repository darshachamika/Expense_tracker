import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/controllers/gemini_advisor_controller.dart';
import '../lib/models/advisor_snapshot.dart';
import '../lib/widgets/gemini_advisor_panel.dart';

AdvisorSnapshot snapshot() => AdvisorSnapshot.calculate(
  now: DateTime(2026, 11, 5),
  expenses: [],
  categories: [],
  bills: [],
  goals: [],
  savedByGoal: {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening/reopening loads once and never asks Gemini', () async {
    var reads = 0;
    var asks = 0;
    final controller = GeminiAdvisorController(
      userId: 'one',
      initialUserId: 'one',
      load: () async {
        reads++;
        return snapshot();
      },
      ask:
          ({
            required String question,
            required AdvisorSnapshot snapshot,
          }) async {
            asks++;
            return 'Answer';
          },
    );
    await controller.ensureLoaded();
    await controller.ensureLoaded();
    expect(reads, 1);
    expect(asks, 0);
    controller.dispose();
  });

  test(
    'every Ask refreshes data; a refresh retains the last answer and draft',
    () async {
      var reads = 0;
      var asks = 0;
      final controller = GeminiAdvisorController(
        userId: 'one',
        initialUserId: 'one',
        load: () async {
          reads++;
          return snapshot();
        },
        ask:
            ({
              required String question,
              required AdvisorSnapshot snapshot,
            }) async {
              asks++;
              return 'Answer $asks';
            },
      );
      controller.setDraft('Question');
      await controller.send();
      await controller.refresh();
      expect(controller.answer, 'Answer 1');
      expect(controller.draft, 'Question');
      await controller.send();
      expect(reads, 3);
      expect(asks, 2);
      expect(controller.answeredQuestion, 'Question');
      controller.dispose();
    },
  );

  test('failed data read prevents a Gemini request', () async {
    var asks = 0;
    final controller = GeminiAdvisorController(
      userId: 'one',
      initialUserId: 'one',
      load: () async => throw StateError('Offline'),
      ask:
          ({
            required String question,
            required AdvisorSnapshot snapshot,
          }) async {
            asks++;
            return 'Answer';
          },
    );
    controller.setDraft('Question');
    await controller.send();
    expect(controller.error, 'Offline');
    expect(controller.snapshot, isNull);
    expect(asks, 0);
    expect(controller.busy, false);
    controller.dispose();
  });

  test('repeated submit while busy creates only one request', () async {
    final pending = Completer<String>();
    var asks = 0;
    final controller = GeminiAdvisorController(
      userId: 'one',
      initialUserId: 'one',
      load: () async => snapshot(),
      ask: ({required String question, required AdvisorSnapshot snapshot}) {
        asks++;
        return pending.future;
      },
    );
    controller.setDraft('Question');
    final work = controller.send();
    await Future<void>.delayed(Duration.zero);
    await controller.send();
    expect(asks, 1);
    pending.complete('Done');
    await work;
    expect(controller.answer, 'Done');
    controller.dispose();
  });

  test(
    'sign-out clears state and ignores an in-flight model response',
    () async {
      final pending = Completer<String>();
      final sessions = StreamController<String?>.broadcast(sync: true);
      final controller = GeminiAdvisorController(
        userId: 'one',
        initialUserId: 'one',
        sessionChanges: sessions.stream,
        load: () async => snapshot(),
        ask: ({required String question, required AdvisorSnapshot snapshot}) =>
            pending.future,
      );
      controller.setDraft('Private question');
      final work = controller.send();
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot, isNotNull);
      sessions.add(null);
      expect(controller.draft, isEmpty);
      expect(controller.snapshot, isNull);
      expect(controller.sessionValid, false);
      pending.complete('Private answer');
      await work;
      expect(controller.answer, isNull);
      expect(controller.busy, false);
      controller.dispose();
      await sessions.close();
    },
  );

  test(
    'disposing during data load prevents any subsequent model request',
    () async {
      final pending = Completer<AdvisorSnapshot>();
      var asks = 0;
      final controller = GeminiAdvisorController(
        userId: 'one',
        initialUserId: 'one',
        load: () => pending.future,
        ask:
            ({
              required String question,
              required AdvisorSnapshot snapshot,
            }) async {
              asks++;
              return 'Answer';
            },
      );
      controller.setDraft('Question');
      final work = controller.send();
      controller.dispose();
      pending.complete(snapshot());
      await work;
      expect(asks, 0);
    },
  );

  testWidgets('compact close/reopen and full panel share draft and answer', (
    tester,
  ) async {
    var asks = 0;
    final controller = GeminiAdvisorController(
      userId: 'one',
      initialUserId: 'one',
      load: () async => snapshot(),
      ask:
          ({
            required String question,
            required AdvisorSnapshot snapshot,
          }) async {
            asks++;
            return 'Retained answer';
          },
    );
    controller.setDraft('Retained question');
    await controller.send();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeminiAdvisorPanel(controller: controller, compact: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GeminiAdvisorPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.answer, 'Retained answer');
    expect(controller.draft, 'Retained question');
    expect(asks, 1);
    expect(find.text('Retained question'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'short phone sheet stays scrollable with keyboard and long text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GeminiAdvisorController(
        userId: 'one',
        initialUserId: 'one',
        load: () async => snapshot(),
        ask: ({
          required String question,
          required AdvisorSnapshot snapshot,
        }) async => 'Long answer ' * 300,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => GeminiAdvisorSheet(controller: controller),
                  ),
                  child: const Text('Open advisor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open advisor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('advisor-question')),
        'Test question',
      );
      tester.view.viewInsets = FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      await controller.send();
      await tester.pumpAndSettle();
      expect(controller.answer, contains('Long answer'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
