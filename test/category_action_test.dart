import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/controllers/gemini_advisor_controller.dart';
import 'package:expense_tracker/models/advisor_snapshot.dart';
import 'package:expense_tracker/models/category_action.dart';

AdvisorSnapshot emptySnapshot() => AdvisorSnapshot.calculate(
  now: DateTime(2026, 11, 5),
  expenses: [],
  categories: [],
  bills: [],
  goals: [],
  savedByGoal: {},
);

CategoryPlan gymPlan(String request) => CategoryPlan.parse(
  '{"intent":"create_category","name":"Gym"}',
  request: request,
);

GeminiAdvisorController categoryController({
  CategoryLookup? lookup,
  CategoryExecutor? execute,
  CategoryPlanner? plan,
  Stream<String?>? sessions,
}) {
  return GeminiAdvisorController(
    userId: 'one',
    initialUserId: 'one',
    sessionChanges: sessions,
    load: () async => emptySnapshot(),
    ask: ({
      required String question,
      required AdvisorSnapshot snapshot,
    }) async => 'Advice',
    planCategory: plan ?? (request) async => gymPlan(request),
    findCategory: lookup ?? (_) async => null,
    createCategory:
        execute ??
        (preview) async =>
            CategoryActionResult(name: preview.name, created: true),
  )..setCategoryMode(true);
}

void main() {
  test('names normalize case/spaces and produce stable short Unicode-safe IDs', () {
    expect(
      categoryActionDocumentId('  GYM  '),
      categoryActionDocumentId('Gym'),
    );
    expect(
      categoryActionDocumentId('Food   Shopping'),
      categoryActionDocumentId('food shopping'),
    );
    expect(
      categoryActionDocumentId('Gym'),
      'aicat_e326cff641fb950a5bdb458e0d52ec6809f041c1618e70bfd22dd61165882aad',
    );
    expect(categoryActionDocumentId('ආහාර'), hasLength(70));
    expect(categoryActionDocumentId('ආහාර'), isNot(contains('/')));
    expect(() => cleanCategoryActionName('Gym\nOther'), throwsFormatException);
    expect(() => cleanCategoryActionName('x' * 61), throwsFormatException);
  });

  test('strict parsing rejects executable fields, unsupported intents and invented names', () {
    for (final data in [
      {'intent': 'delete_category', 'name': 'Gym'},
      {'intent': 'create_category', 'name': 'Gym', 'userId': 'another-user'},
      {'intent': 'create_category', 'name': 'Invented'},
      {'intent': 'create_category', 'name': ''},
      {'intent': 'unsupported', 'name': 'Gym'},
    ]) {
      expect(
        () => CategoryPlan.parse(jsonEncode(data), request: 'Create Gym'),
        throwsFormatException,
      );
    }
    final sinhala = CategoryPlan.parse(
      '{"intent":"create_category","name":"ආහාර"}',
      request: 'ආහාර කියලා category එකක් හදන්න',
    );
    expect(sinhala.name, 'ආහාර');
  });

  test('preview checks existing names and never executes a write', () async {
    var writes = 0;
    final controller = categoryController(
      execute: (preview) async {
        writes++;
        return CategoryActionResult(name: preview.name, created: true);
      },
    );
    controller.setDraft('Create Gym');
    await controller.send();
    expect(controller.pendingCategory?.name, 'Gym');
    expect(writes, 0);
    expect(controller.actionMessage, isNull);
    controller.dispose();
  });

  test('Cancel drops the preview; a later Confirm cannot execute it', () async {
    var writes = 0;
    final controller = categoryController(
      execute: (preview) async {
        writes++;
        return CategoryActionResult(name: preview.name, created: true);
      },
    );
    controller.setDraft('Create Gym');
    await controller.send();
    controller.cancelCategory();
    await controller.confirmCategory();
    expect(controller.pendingCategory, isNull);
    expect(writes, 0);
    expect(controller.actionMessage, contains('Cancelled'));
    controller.dispose();
  });

  test('editing or switching modes invalidates the pending preview', () async {
    var writes = 0;
    final controller = categoryController(
      execute: (preview) async {
        writes++;
        return CategoryActionResult(name: preview.name, created: true);
      },
    );
    controller.setDraft('Create Gym');
    await controller.send();
    controller.setDraft('Create Travel');
    await controller.confirmCategory();
    expect(writes, 0);
    controller.setDraft('Create Gym');
    await controller.send();
    controller.setCategoryMode(false);
    await controller.confirmCategory();
    expect(writes, 0);
    expect(controller.pendingCategory, isNull);
    controller.dispose();
  });

  test(
    'existing archived category shows restore guidance without a write',
    () async {
      var writes = 0;
      final controller = categoryController(
        lookup: (_) async =>
            const CategoryActionResult(name: 'Gym', archived: true),
        execute: (preview) async {
          writes++;
          return CategoryActionResult(name: preview.name, created: true);
        },
      );
      controller.setDraft('Create Gym');
      await controller.send();
      await controller.confirmCategory();
      expect(controller.pendingCategory, isNull);
      expect(controller.actionMessage, contains('Restore'));
      expect(writes, 0);
      controller.dispose();
    },
  );

  test(
    'Confirm uses the immutable preview and double-click executes once',
    () async {
      final pending = Completer<CategoryActionResult>();
      final captured = <CategoryActionPreview>[];
      final controller = categoryController(
        execute: (preview) {
          captured.add(preview);
          return pending.future;
        },
      );
      controller.setDraft('Create Gym');
      await controller.send();
      final preview = controller.pendingCategory;
      final work = controller.confirmCategory();
      await controller.confirmCategory();
      expect(controller.busy, true);
      expect(captured, hasLength(1));
      expect(identical(captured.single, preview), true);
      expect(controller.actionMessage, isNull);
      pending.complete(const CategoryActionResult(name: 'Gym', created: true));
      await work;
      expect(controller.actionMessage, 'Category created: Gym.');
      expect(controller.pendingCategory, isNull);
      await controller.confirmCategory();
      expect(captured, hasLength(1));
      controller.dispose();
    },
  );

  test('unknown save outcome retains the same ID for explicit retry', () async {
    final documents = <String>{};
    var attempts = 0;
    final ids = <String>[];
    final controller = categoryController(
      execute: (preview) async {
        attempts++;
        ids.add(preview.documentId);
        if (attempts == 1) {
          documents.add(preview.documentId);
          throw StateError('Acknowledgement lost');
        }
        return CategoryActionResult(
          name: preview.name,
          created: documents.add(preview.documentId),
        );
      },
    );
    controller.setDraft('Create Gym');
    await controller.send();
    await controller.confirmCategory();
    expect(controller.error, contains('Save could not be confirmed'));
    expect(controller.pendingCategory, isNotNull);
    expect(controller.actionMessage, isNull);
    await controller.confirmCategory();
    expect(ids[0], ids[1]);
    expect(documents, hasLength(1));
    expect(controller.actionMessage, contains('already exists'));
    controller.dispose();
  });

  test('account change clears pending preview and blocks execution', () async {
    final sessions = StreamController<String?>.broadcast(sync: true);
    var writes = 0;
    final controller = categoryController(
      sessions: sessions.stream,
      execute: (preview) async {
        writes++;
        return CategoryActionResult(name: preview.name, created: true);
      },
    );
    controller.setDraft('Create Gym');
    await controller.send();
    sessions.add('another-user');
    await controller.confirmCategory();
    expect(controller.pendingCategory, isNull);
    expect(controller.draft, isEmpty);
    expect(writes, 0);
    controller.dispose();
    await sessions.close();
  });

  test('unsupported requests do not leave executable previews', () async {
    final controller = categoryController(
      plan: (request) async => CategoryPlan.parse(
        '{"intent":"unsupported","name":""}',
        request: request,
      ),
    );
    controller.setDraft('Delete Gym');
    await controller.send();
    expect(controller.pendingCategory, isNull);
    expect(controller.actionMessage, contains('creating one category only'));
    controller.dispose();
  });
}
