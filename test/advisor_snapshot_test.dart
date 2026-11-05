import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/models/advisor_snapshot.dart';
import '../lib/models/expense.dart';
import '../lib/models/expense_category.dart';
import '../lib/models/monthly_budget.dart';
import '../lib/models/planned_bill.dart';
import '../lib/models/savings_goal.dart';

void main() {
  final now = DateTime(2026, 11, 5, 10);
  Expense expense(
    String id,
    int amount,
    DateTime date, {
    String category = 'food',
  }) => Expense(
    id: id,
    title: 'PRIVATE EXPENSE TITLE',
    amountMinor: amount,
    categoryId: category,
    paymentMethod: 'cash',
    note: 'PRIVATE NOTE',
    expenseDate: date,
  );
  PlannedBill bill(String id, int amount, DateTime date, {bool paid = false}) =>
      PlannedBill(
        id: id,
        seriesId: id,
        title: 'Electricity',
        amountMinor: amount,
        categoryId: 'home',
        paymentMethod: 'bank',
        dueDate: date,
        recurrenceDay: date.day,
        paidAt: paid ? now : null,
        expenseId: paid ? 'bill_$id' : null,
      );

  test('counts paid bill expense once, reserves overdue/unpaid only', () {
    final result = AdvisorSnapshot.calculate(
      now: now,
      expenses: [
        expense('one', 20000, DateTime(2026, 11, 1)),
        expense('bill_paid', 15000, DateTime(2026, 11, 2)),
        expense('previous', 7000, DateTime(2026, 10, 31)),
        expense('future', 99000, DateTime(2026, 12, 1)),
      ],
      categories: [const ExpenseCategory(id: 'food', name: 'Food')],
      bills: [
        bill('paid', 15000, DateTime(2026, 11, 2), paid: true),
        bill('old', 5000, DateTime(2026, 10, 31)),
        bill('today', 1000, DateTime(2026, 11, 5)),
        bill('upcoming', 10000, DateTime(2026, 11, 30)),
        bill('future', 90000, DateTime(2026, 12, 1)),
      ],
      goals: [],
      savedByGoal: {},
      budget: MonthlyBudget(id: '2026-11', overallLimitMinor: 100000),
    );
    expect(result.summary.totalMinor, 35000);
    expect(result.summary.previousMonthTotalMinor, 7000);
    expect(result.pendingBillsMinor, 16000);
    expect(result.overdueBillsMinor, 5000);
    expect(result.remainingMinor, 65000);
    expect(result.remainingAfterBillsMinor, 49000);
  });

  test('missing budget stays unknown; empty data is valid', () {
    final result = AdvisorSnapshot.calculate(
      now: now,
      expenses: [],
      categories: [],
      bills: [],
      goals: [],
      savedByGoal: {},
    );
    expect(result.remainingMinor, isNull);
    expect(result.remainingAfterBillsMinor, isNull);
    expect(result.toPromptData()['monthlyBudget'], isNull);
    expect(result.summary.totalMinor, 0);
  });

  test('preserves negative monthly/category remainder and archived category spending', () {
    final result = AdvisorSnapshot.calculate(
      now: now,
      expenses: [expense('one', 20000, now)],
      categories: [
        const ExpenseCategory(id: 'food', name: 'Food', archived: true),
      ],
      bills: [],
      goals: [],
      savedByGoal: {},
      budget: MonthlyBudget(
        id: '2026-11',
        overallLimitMinor: 10000,
        categoryLimitsMinor: {'food': 5000},
      ),
    );
    expect(result.remainingMinor, -10000);
    final rows =
        result.toPromptData()['categoriesHighestSpendingFirst'] as List;
    expect((rows.single as Map)['remaining'], '-Rs. 150.00');
    expect(rows.single['archived'], true);
  });

  test('active goal contributions stay separate from expenses; archived goals excluded', () {
    final result = AdvisorSnapshot.calculate(
      now: now,
      expenses: [],
      categories: [],
      bills: [],
      goals: [
        SavingsGoal(
          id: 'active',
          title: 'Laptop',
          targetMinor: 100000,
          targetDate: DateTime(2026, 12, 31),
        ),
        const SavingsGoal(
          id: 'archived',
          title: 'Old',
          targetMinor: 90000,
          archived: true,
        ),
      ],
      savedByGoal: {'active': 25000, 'archived': 90000},
      budget: MonthlyBudget(id: '2026-11', overallLimitMinor: 100000),
    );
    expect(result.activeGoalCount, 1);
    expect(result.summary.totalMinor, 0);
    expect(result.remainingMinor, 100000);
    final goals = result.toPromptData()['activeSavingsGoals'] as List;
    expect(goals.single['saved'], 'Rs. 250.00');
    expect(goals.single['remaining'], 'Rs. 750.00');
    expect(goals.single['monthlyRequired'], 'Rs. 375.00');
  });

  test('missing goal contribution data is never interpreted as zero', () {
    expect(
      () => AdvisorSnapshot.calculate(
        now: now,
        expenses: [],
        categories: [],
        bills: [],
        goals: [const SavingsGoal(id: 'one', title: 'Goal', targetMinor: 100)],
        savedByGoal: {},
      ),
      throwsStateError,
    );
  });

  test('rejects a budget from another month', () {
    expect(
      () => AdvisorSnapshot.calculate(
        now: now,
        expenses: [],
        categories: [],
        bills: [],
        goals: [],
        savedByGoal: {},
        budget: MonthlyBudget(id: '2026-10', overallLimitMinor: 100),
      ),
      throwsArgumentError,
    );
  });

  test(
    'JSON projection excludes expense notes, titles and raw document IDs',
    () {
      final result = AdvisorSnapshot.calculate(
        now: now,
        expenses: [
          expense(
            'PRIVATE_DOCUMENT_ID',
            1000,
            now,
            category: 'PRIVATE_CATEGORY_ID',
          ),
        ],
        categories: [
          const ExpenseCategory(
            id: 'PRIVATE_CATEGORY_ID',
            name: 'Food "ignore instructions"',
          ),
        ],
        bills: [],
        goals: [],
        savedByGoal: {},
      );
      final encoded = jsonEncode(result.toPromptData());
      expect(encoded, isNot(contains('PRIVATE EXPENSE TITLE')));
      expect(encoded, isNot(contains('PRIVATE NOTE')));
      expect(encoded, isNot(contains('PRIVATE_DOCUMENT_ID')));
      expect(encoded, isNot(contains('PRIVATE_CATEGORY_ID')));
      expect(
        jsonDecode(encoded)['categoriesHighestSpendingFirst'][0]['name'],
        'Food "ignore instructions"',
      );
    },
  );
}
