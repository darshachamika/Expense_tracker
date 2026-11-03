import 'package:flutter_test/flutter_test.dart';

import '../lib/models/expense.dart';
import '../lib/models/monthly_expense_summary.dart';

Expense expense({
  required String id,
  required int amountMinor,
  required DateTime date,
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
  test('groups selected month and excludes adjacent months', () {
    final summary = MonthlyExpenseSummary.fromExpenses(
      month: DateTime(2026, 11),
      now: DateTime(2026, 11, 3),
      expenses: [
        expense(
          id: 'previous',
          amountMinor: 10000,
          date: DateTime(2026, 10, 31, 23, 59),
        ),
        expense(id: 'first', amountMinor: 125050, date: DateTime(2026, 11, 1)),
        expense(
          id: 'second',
          amountMinor: 50025,
          date: DateTime(2026, 11, 2),
          categoryId: 'transport',
        ),
        expense(id: 'next', amountMinor: 90000, date: DateTime(2026, 12, 1)),
      ],
    );

    expect(summary.totalMinor, 175075);
    expect(summary.previousMonthTotalMinor, 10000);
    expect(summary.expenseCount, 2);
    expect(summary.categoryTotalsMinor['food'], 125050);
    expect(summary.categoryTotalsMinor['transport'], 50025);
    expect(summary.dailyTotalsMinor[1], 125050);
    expect(summary.dailyTotalsMinor[3], 0);
    expect(summary.dailyTotalsMinor.length, 30);
    expect(summary.averageDayCount, 3);
    expect(summary.averageDailyMinor, 58358);
    expect(summary.changePercent, closeTo(1650.75, 0.001));
  });

  test('handles an empty leap-year month without dividing by zero', () {
    final summary = MonthlyExpenseSummary.fromExpenses(
      month: DateTime(2024, 2),
      now: DateTime(2026, 11, 3),
      expenses: [],
    );

    expect(summary.totalMinor, 0);
    expect(summary.expenseCount, 0);
    expect(summary.dailyTotalsMinor.length, 29);
    expect(summary.averageDayCount, 29);
    expect(summary.averageDailyMinor, 0);
    expect(summary.changePercent, isNull);
  });

  test('handles previous month across a year boundary', () {
    final summary = MonthlyExpenseSummary.fromExpenses(
      month: DateTime(2026, 1),
      now: DateTime(2026, 2, 1),
      expenses: [
        expense(
          id: 'december',
          amountMinor: 20000,
          date: DateTime(2025, 12, 31),
        ),
        expense(id: 'january', amountMinor: 10000, date: DateTime(2026, 1, 31)),
      ],
    );

    expect(summary.totalMinor, 10000);
    expect(summary.previousMonthTotalMinor, 20000);
    expect(summary.averageDayCount, 31);
    expect(summary.changePercent, -50.0);
  });
}
