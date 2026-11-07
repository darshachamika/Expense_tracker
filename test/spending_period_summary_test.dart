import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/spending_period_summary.dart';

Expense expense(
  String id,
  int amountMinor,
  DateTime date, {
  String categoryId = 'food',
}) {
  return Expense(
    id: id,
    title: 'Test expense',
    amountMinor: amountMinor,
    categoryId: categoryId,
    paymentMethod: 'cash',
    expenseDate: date,
  );
}

void main() {
  final now = DateTime(2026, 3, 15, 12);

  test('year to date includes today and excludes future expenses', () {
    final summary = SpendingPeriodSummary.forYear(
      year: 2026,
      now: now,
      expenses: [
        expense('old-year', 90000, DateTime(2025, 12, 31)),
        expense('jan', 10000, DateTime(2026, 1, 1)),
        expense(
          'today',
          20000,
          DateTime(2026, 3, 15, 23, 59),
          categoryId: 'transport',
        ),
        expense('tomorrow', 50000, DateTime(2026, 3, 16)),
        expense('future-month', 80000, DateTime(2026, 4, 1)),
      ],
    );

    expect(summary.totalMinor, 30000);
    expect(summary.expenseCount, 2);
    expect(summary.monthCount, 3);
    expect(summary.monthlyTotalsMinor[DateTime(2026, 2)], 0);
    expect(summary.monthlyTotalsMinor.containsKey(DateTime(2026, 4)), isFalse);
    expect(summary.averageMonthlyMinor, 10000);
    expect(summary.highestSpendingMonth, DateTime(2026, 3));
    expect(summary.categoryTotalsMinor['transport'], 20000);
  });

  test('a completed year includes all twelve months', () {
    final summary = SpendingPeriodSummary.forYear(
      year: 2025,
      now: now,
      expenses: [
        expense('last-day', 120000, DateTime(2025, 12, 31, 23, 59)),
        expense('next-year', 50000, DateTime(2026, 1, 1)),
      ],
    );

    expect(summary.totalMinor, 120000);
    expect(summary.monthCount, 12);
    expect(summary.averageMonthlyMinor, 10000);
    expect(summary.highestSpendingMonth, DateTime(2025, 12));
  });

  test('all time includes empty months from first expense through today', () {
    final summary = SpendingPeriodSummary.allTime(
      now: now,
      expenses: [
        expense('first', 10000, DateTime(2025, 12, 10)),
        expense('second', 30000, DateTime(2026, 2, 5)),
        expense('future', 90000, DateTime(2026, 4, 1)),
      ],
    );

    expect(summary.totalMinor, 40000);
    expect(summary.expenseCount, 2);
    expect(summary.monthCount, 4);
    expect(summary.monthlyTotalsMinor[DateTime(2026, 1)], 0);
    expect(summary.monthlyTotalsMinor[DateTime(2026, 3)], 0);
    expect(summary.averageMonthlyMinor, 10000);
    expect(summary.firstExpenseDate, DateTime(2025, 12, 10));
    expect(summary.highestSpendingMonth, DateTime(2026, 2));
  });

  test('empty history returns zero totals and no highest month', () {
    final summary = SpendingPeriodSummary.allTime(expenses: [], now: now);

    expect(summary.totalMinor, 0);
    expect(summary.expenseCount, 0);
    expect(summary.averageMonthlyMinor, 0);
    expect(summary.monthlyTotalsMinor, isEmpty);
    expect(summary.firstExpenseDate, isNull);
    expect(summary.highestSpendingMonth, isNull);
  });
}
