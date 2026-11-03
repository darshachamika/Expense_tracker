import 'expense.dart';
import 'monthly_budget.dart';
import 'planned_bill.dart';

class PurchaseSimulation {
  final int purchaseAmountMinor;
  final int monthlySpentMinor;
  final int categorySpentMinor;
  final int pendingBillsMinor;

  final int? monthlyLimitMinor;
  final int? categoryLimitMinor;

  const PurchaseSimulation._({
    required this.purchaseAmountMinor,
    required this.monthlySpentMinor,
    required this.categorySpentMinor,
    required this.pendingBillsMinor,
    required this.monthlyLimitMinor,
    required this.categoryLimitMinor,
  });

  int get monthlySpentAfterMinor => monthlySpentMinor + purchaseAmountMinor;

  int? get monthlyRemainingBeforeMinor {
    final limit = monthlyLimitMinor;
    return limit == null ? null : limit - monthlySpentMinor;
  }

  int? get monthlyRemainingAfterMinor {
    final limit = monthlyLimitMinor;
    return limit == null ? null : limit - monthlySpentAfterMinor;
  }

  int? get categoryRemainingAfterMinor {
    final limit = categoryLimitMinor;

    return limit == null
        ? null
        : limit - categorySpentMinor - purchaseAmountMinor;
  }

  /// Remaining monthly budget after the proposed purchase
  /// and the recorded pending bills.
  ///
  /// This is a budget estimate, not a bank balance.
  int? get remainingAfterBillsMinor {
    final remaining = monthlyRemainingAfterMinor;

    return remaining == null ? null : remaining - pendingBillsMinor;
  }

  factory PurchaseSimulation.calculate({
    required int purchaseAmountMinor,
    required String categoryId,
    required DateTime purchaseDate,
    required List<Expense> expenses,
    required List<PlannedBill> bills,
    MonthlyBudget? budget,
  }) {
    if (purchaseAmountMinor <= 0 || purchaseAmountMinor > 99999999999) {
      throw ArgumentError('Enter a positive supported purchase amount.');
    }

    if (categoryId.trim().isEmpty) {
      throw ArgumentError('Select a category.');
    }

    final date = purchaseDate.toLocal();
    final monthStart = DateTime(date.year, date.month);
    final nextMonth = DateTime(date.year, date.month + 1);

    if (budget != null && budget.id != MonthlyBudget.monthKey(monthStart)) {
      throw ArgumentError('Budget does not match the purchase month.');
    }

    var monthlySpent = 0;
    var categorySpent = 0;
    var pendingBills = 0;

    for (final expense in expenses) {
      final expenseDate = expense.expenseDate.toLocal();

      if (expenseDate.isBefore(monthStart) ||
          !expenseDate.isBefore(nextMonth)) {
        continue;
      }

      monthlySpent += expense.amountMinor;

      if (expense.categoryId == categoryId) {
        categorySpent += expense.amountMinor;
      }
    }

    for (final bill in bills) {
      // Reserve recorded unpaid bills due before the month ends,
      // including overdue bills from earlier months.
      if (!bill.isPaid && bill.dueDate.toLocal().isBefore(nextMonth)) {
        pendingBills += bill.amountMinor;
      }
    }

    return PurchaseSimulation._(
      purchaseAmountMinor: purchaseAmountMinor,
      monthlySpentMinor: monthlySpent,
      categorySpentMinor: categorySpent,
      pendingBillsMinor: pendingBills,
      monthlyLimitMinor: budget?.overallLimitMinor,
      categoryLimitMinor: budget?.categoryLimitsMinor[categoryId],
    );
  }
}
