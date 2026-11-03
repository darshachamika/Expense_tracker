import 'expense.dart';

class MonthlyExpenseSummary {
  final DateTime month;
  final int totalMinor;
  final int previousMonthTotalMinor;
  final int expenseCount;
  final int averageDayCount;

  /// Category ID -> total spending in minor units.
  final Map<String, int> categoryTotalsMinor;

  /// Day of month -> total spending in minor units.
  /// Includes days with zero spending.
  final Map<int, int> dailyTotalsMinor;

  MonthlyExpenseSummary._({
    required this.month,
    required this.totalMinor,
    required this.previousMonthTotalMinor,
    required this.expenseCount,
    required this.averageDayCount,
    required Map<String, int> categoryTotalsMinor,
    required Map<int, int> dailyTotalsMinor,
  }) : categoryTotalsMinor = Map.unmodifiable(categoryTotalsMinor),
       dailyTotalsMinor = Map.unmodifiable(dailyTotalsMinor);

  /// Rounded to the nearest minor unit using integer arithmetic.
  int get averageDailyMinor {
    return (totalMinor + averageDayCount ~/ 2) ~/ averageDayCount;
  }

  /// Null means the previous month had no spending,
  /// so a percentage comparison is unavailable.
  double? get changePercent {
    if (previousMonthTotalMinor == 0) return null;

    return (totalMinor - previousMonthTotalMinor) /
        previousMonthTotalMinor *
        100;
  }

  factory MonthlyExpenseSummary.fromExpenses({
    required List<Expense> expenses,
    required DateTime month,
    DateTime? now,
  }) {
    final selectedMonth = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final previousMonth = DateTime(month.year, month.month - 1);
    final today = (now ?? DateTime.now()).toLocal();

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final isCurrentMonth =
        today.year == selectedMonth.year && today.month == selectedMonth.month;

    // Current month: average through today.
    // Other months: average across the complete calendar month.
    final averageDayCount = isCurrentMonth ? today.day : daysInMonth;

    final categoryTotals = <String, int>{};
    final dailyTotals = <int, int>{
      for (var day = 1; day <= daysInMonth; day++) day: 0,
    };

    var totalMinor = 0;
    var previousMonthTotalMinor = 0;
    var expenseCount = 0;

    for (final expense in expenses) {
      final date = expense.expenseDate.toLocal();

      if (!date.isBefore(selectedMonth) && date.isBefore(nextMonth)) {
        totalMinor += expense.amountMinor;
        expenseCount++;

        categoryTotals.update(
          expense.categoryId,
          (total) => total + expense.amountMinor,
          ifAbsent: () => expense.amountMinor,
        );

        dailyTotals.update(date.day, (total) => total + expense.amountMinor);
      } else if (!date.isBefore(previousMonth) &&
          date.isBefore(selectedMonth)) {
        previousMonthTotalMinor += expense.amountMinor;
      }
    }

    return MonthlyExpenseSummary._(
      month: selectedMonth,
      totalMinor: totalMinor,
      previousMonthTotalMinor: previousMonthTotalMinor,
      expenseCount: expenseCount,
      averageDayCount: averageDayCount,
      categoryTotalsMinor: categoryTotals,
      dailyTotalsMinor: dailyTotals,
    );
  }
}
