import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/monthly_budget.dart';
import 'package:expense_tracker/models/planned_bill.dart';
import 'package:expense_tracker/models/purchase_simulation.dart';

void main() {
  final date = DateTime(2026, 11, 4);

  final expenses = [
    Expense(
      id: 'expense-1',
      title: 'Food',
      amountMinor: 20000,
      categoryId: 'food',
      paymentMethod: 'cash',
      expenseDate: DateTime(2026, 11, 1),
    ),
  ];

  PlannedBill bill(String id, DateTime dueDate, {bool paid = false}) {
    return PlannedBill(
      id: id,
      seriesId: id,
      title: 'Test bill',
      amountMinor: 15000,
      categoryId: 'home',
      paymentMethod: 'bank',
      dueDate: dueDate,
      recurrenceDay: dueDate.day,
      paidAt: paid ? date : null,
      expenseId: paid ? 'bill_$id' : null,
    );
  }

  test('calculates purchase impact and reserves only pending bills', () {
    final result = PurchaseSimulation.calculate(
      purchaseAmountMinor: 10000,
      categoryId: 'food',
      purchaseDate: date,
      expenses: expenses,
      budget: MonthlyBudget(
        id: '2026-11',
        overallLimitMinor: 100000,
        categoryLimitsMinor: {'food': 30000},
      ),
      bills: [
        bill('overdue', DateTime(2026, 10, 31)),
        bill('upcoming', DateTime(2026, 11, 30)),
        bill('future', DateTime(2026, 12, 1)),
        bill('paid', DateTime(2026, 11, 1), paid: true),
      ],
    );

    expect(result.monthlyRemainingBeforeMinor, 80000);
    expect(result.monthlySpentAfterMinor, 30000);
    expect(result.monthlyRemainingAfterMinor, 70000);
    expect(result.categoryRemainingAfterMinor, 0);
    expect(result.pendingBillsMinor, 30000);
    expect(result.remainingAfterBillsMinor, 40000);
  });

  test('does not invent a balance when no budget exists', () {
    final result = PurchaseSimulation.calculate(
      purchaseAmountMinor: 10000,
      categoryId: 'food',
      purchaseDate: date,
      expenses: expenses,
      bills: [],
    );

    expect(result.monthlySpentAfterMinor, 30000);
    expect(result.monthlyRemainingAfterMinor, isNull);
    expect(result.categoryRemainingAfterMinor, isNull);
    expect(result.remainingAfterBillsMinor, isNull);
  });

  test('preserves negative remaining amounts when over budget', () {
    final result = PurchaseSimulation.calculate(
      purchaseAmountMinor: 20000,
      categoryId: 'food',
      purchaseDate: date,
      expenses: expenses,
      bills: [],
      budget: MonthlyBudget(id: '2026-11', overallLimitMinor: 30000),
    );

    expect(result.monthlyRemainingAfterMinor, -10000);
  });
}
