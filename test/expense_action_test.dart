import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/controllers/gemini_advisor_controller.dart';
import '../lib/models/advisor_snapshot.dart';
import '../lib/models/expense.dart';
import '../lib/models/expense_action.dart';
import '../lib/widgets/gemini_advisor_panel.dart';

ExpenseActionPlan planFor(ExpenseActionInput input, {
  String title = 'lunch',
  String category = 'Food',
  String payment = 'unspecified',
}) => ExpenseActionPlan.parse(jsonEncode({
  'intent': 'createExpense',
  'title': title,
  'category': category,
  'paymentMethod': payment,
  'dateReference': input.explicitDate ? 'explicit' : 'today',
}), input)!;

ExpenseActionPreview previewFor(ExpenseActionInput input, ExpenseActionPlan plan) =>
    ExpenseActionPreview(
      userId: 'alice',
      expense: Expense(
        id: 'advisor_abcdefghijklmnopqrst',
        title: plan.title,
        amountMinor: input.amountMinor,
        categoryId: 'food',
        paymentMethod: plan.paymentMethod,
        expenseDate: input.date,
      ),
      categoryName: 'Food & Drinks',
      defaultPayment: plan.defaultPayment,
      defaultDate: !input.explicitDate,
    );

GeminiAdvisorController controllerFor({
  required ExpenseExecutor save,
  ExpensePlanner? planner,
}) => GeminiAdvisorController(
  userId: 'alice',
  initialUserId: 'alice',
  load: () async => AdvisorSnapshot.calculate(
    now: DateTime.now(), expenses: [], categories: [], bills: [],
    goals: [], savedByGoal: {},
  ),
  ask: ({required question, required snapshot}) async => 'Advice',
  planExpense: planner ?? (input) async => planFor(input),
  buildExpensePreview: (input, plan) async => previewFor(input, plan),
  saveExpense: save,
);

Future<void> prepare(GeminiAdvisorController controller) async {
  controller.setMode(AdvisorMode.expense);
  controller.setDraft('Add lunch Rs. 650 to Food today');
  await controller.send();
  expect(controller.error, isNull);
  expect(controller.pendingExpense, isNotNull);
}

void main() {
  final now = DateTime(2026, 11, 7, 14);

  test('rupees become integer cents and omitted date uses local today', () {
    final input = ExpenseActionInput.parse('Add lunch Rs. 1,250.05 to Food', now: now);
    expect(input.amountMinor, 125005);
    expect(input.date, DateTime(2026, 11, 7));
    expect(input.explicitDate, isFalse);
    final plan = planFor(input);
    expect(plan.paymentMethod, 'cash');
    expect(plan.defaultPayment, isTrue);
  });

  test('Sinhala request suffix is accepted without changing the amount', () {
    final input = ExpenseActionInput.parse(
      'අද lunch එකට Rs. 650ක් Food category එකට add කරන්න', now: now,
    );
    expect(input.amountMinor, 65000);
  });

  test('ISO date is removed before parsing one amount', () {
    final input = ExpenseActionInput.parse(
      'Add lunch Rs. 650 to Food on 2026-11-05 using card', now: now,
    );
    expect(input.date, DateTime(2026, 11, 5));
    expect(input.instruction, isNot(contains('2026-11-05')));
    final plan = planFor(input, payment: 'card');
    expect(plan.paymentMethod, 'card');
    expect(plan.defaultPayment, isFalse);
  });

  test('invalid dates, future dates and multiple dates are rejected', () {
    for (final date in ['2026-02-30', '2026-11-08', '1999-12-31', '2026-01-01 2026-01-02']) {
      expect(() => ExpenseActionInput.parse('Add lunch Rs. 650 to Food on $date', now: now),
        throwsFormatException);
    }
  });

  test('ambiguous amounts, precision, currency and multipliers are rejected', () {
    for (final amount in ['0', '-650', '650.001', '1,25', '650 and 200', '5k', r'$650', '650 USD', '650%']) {
      expect(() => ExpenseActionInput.parse('Add lunch $amount to Food', now: now),
        throwsFormatException, reason: amount);
    }
  });

  test('model cannot invent title or category', () {
    final input = ExpenseActionInput.parse('Add lunch Rs. 650 to Food', now: now);
    expect(() => planFor(input, title: 'dinner'), throwsFormatException);
    expect(() => planFor(input, category: 'Shopping'), throwsFormatException);
    expect(() => planFor(input, payment: 'bitcoin'), throwsFormatException);
  });

  test('preview validates owner and preserves the reviewed calendar date', () {
    final input = ExpenseActionInput.parse('Add lunch Rs. 650 to Food', now: now);
    final preview = previewFor(input, planFor(input));
    preview.validate('alice', now);
    expect(preview.dateLabel, '2026-11-07');
    expect(() => preview.validate('bob', now), throwsStateError);
  });

  test('preview and cancellation make no save call', () async {
    var writes = 0;
    final controller = controllerFor(save: (_) async { writes++; return true; });
    addTearDown(controller.dispose);
    await prepare(controller);
    expect(writes, 0);
    controller.cancelExpense();
    await controller.confirmExpense();
    expect(writes, 0);
    expect(controller.pendingExpense, isNull);
  });

  test('editing the request invalidates an unconfirmed preview', () async {
    final controller = controllerFor(save: (_) async => true);
    addTearDown(controller.dispose);
    await prepare(controller);
    controller.setDraft('Add lunch Rs. 700 to Food');
    expect(controller.pendingExpense, isNull);
  });

  test('double confirmation makes one save call while in flight', () async {
    var writes = 0;
    final saved = Completer<bool>();
    final controller = controllerFor(save: (_) { writes++; return saved.future; });
    addTearDown(controller.dispose);
    await prepare(controller);
    final first = controller.confirmExpense();
    await controller.confirmExpense();
    expect(writes, 1);
    expect(controller.busy, isTrue);
    saved.complete(true);
    await first;
    expect(controller.pendingExpense, isNull);
    expect(controller.draft, isEmpty);
    expect(controller.actionMessage, startsWith('Expense saved'));
  });

  test('uncertain save retains the same ID and blocks replacing the request', () async {
    final ids = <String>[];
    final controller = controllerFor(save: (preview) async {
      ids.add(preview.expense.id);
      if (ids.length == 1) throw StateError('Connection lost');
      return false;
    });
    addTearDown(controller.dispose);
    await prepare(controller);
    await controller.confirmExpense();
    expect(controller.expenseRetryRequired, isTrue);
    controller.setDraft('another request');
    controller.setMode(AdvisorMode.budget);
    await controller.send();
    expect(controller.expenseMode, isTrue);
    expect(controller.draft, contains('lunch'));
    await controller.confirmExpense();
    expect(ids.length, 2);
    expect(ids.first, ids.last);
    expect(controller.actionMessage, contains('already saved'));
    expect(controller.expenseRetryRequired, isFalse);
  });

  test('category conflict discards the preview and requires another review', () async {
    final controller = controllerFor(save: (_) async => throw const ExpensePreviewChanged());
    addTearDown(controller.dispose);
    await prepare(controller);
    await controller.confirmExpense();
    expect(controller.pendingExpense, isNull);
    expect(controller.error, contains('category changed'));
    expect(controller.saveAttempted, isFalse);
  });

  test('sign out discards an in-flight plan', () async {
    final planned = Completer<ExpenseActionPlan?>();
    final controller = controllerFor(save: (_) async => true, planner: (_) => planned.future);
    addTearDown(controller.dispose);
    controller.setMode(AdvisorMode.expense);
    controller.setDraft('Add lunch Rs. 650 to Food');
    final pending = controller.send();
    controller.invalidateSession();
    final input = ExpenseActionInput.parse('Add lunch Rs. 650 to Food', now: now);
    planned.complete(planFor(input));
    await pending;
    expect(controller.pendingExpense, isNull);
    expect(controller.draft, isEmpty);
    expect(controller.sessionValid, isFalse);
  });

  testWidgets('panel presents reviewed fields and requires explicit confirmation', (tester) async {
    var writes = 0;
    final controller = controllerFor(save: (_) async { writes++; return true; });
    addTearDown(controller.dispose);
    await prepare(controller);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GeminiAdvisorPanel(controller: controller))));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Confirm expense');
    await tester.scrollUntilVisible(confirm, 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Category: Food & Drinks'), findsOneWidget);
    expect(find.text('Payment: cash (default)'), findsOneWidget);
    expect(writes, 0);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(controller.actionMessage, contains('Expense saved'));
  });
}
