import 'expense.dart';

class SpendingPeriodSummary {
  final int totalMinor;
  final int expenseCount;
  final DateTime? firstExpenseDate;

  /// Month start -> spending in minor units.
  /// Includes elapsed months with no spending.
  final Map<DateTime, int> monthlyTotalsMinor;

  /// Category ID -> spending in minor units.
  final Map<String, int> categoryTotalsMinor;

  SpendingPeriodSummary._({
    required this.totalMinor,
    required this.expenseCount,
    required this.firstExpenseDate,
    required Map<DateTime, int> monthlyTotalsMinor,
    required Map<String, int> categoryTotalsMinor,
  }) : monthlyTotalsMinor = Map.unmodifiable(monthlyTotalsMinor),
       categoryTotalsMinor = Map.unmodifiable(categoryTotalsMinor);

  int get monthCount => monthlyTotalsMinor.length;

  /// Rounded average across all months in the displayed period,
  /// including months with zero spending.
  int get averageMonthlyMinor {
    if (monthCount == 0) return 0;

    return (totalMinor + monthCount ~/ 2) ~/ monthCount;
  }

  /// Returns null when there is no spending.
  /// If months tie, returns the earliest month.
  DateTime? get highestSpendingMonth {
    DateTime? highestMonth;
    var highestAmount = 0;

    for (final entry in monthlyTotalsMinor.entries) {
      if (entry.value > highestAmount) {
        highestAmount = entry.value;
        highestMonth = entry.key;
      }
    }

    return highestMonth;
  }

  factory SpendingPeriodSummary.forYear({
    required List<Expense> expenses,
    required int year,
    DateTime? now,
  }) {
    if (year < 2000 || year > 9999) {
      throw ArgumentError('Year must be between 2000 and 9999.');
    }

    final today = (now ?? DateTime.now()).toLocal();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    final start = DateTime(year);
    final nextYear = DateTime(year + 1);
    final end = nextYear.isBefore(tomorrow) ? nextYear : tomorrow;

    final monthsToShow = year < today.year
        ? 12
        : year == today.year
        ? today.month
        : 0;

    final monthlyTotals = <DateTime, int>{
      for (var month = 1; month <= monthsToShow; month++)
        DateTime(year, month): 0,
    };

    return SpendingPeriodSummary._calculate(
      expenses: expenses,
      start: start,
      endExclusive: end,
      monthlyTotals: monthlyTotals,
    );
  }

  factory SpendingPeriodSummary.allTime({
    required List<Expense> expenses,
    DateTime? now,
  }) {
    final today = (now ?? DateTime.now()).toLocal();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    final recordedExpenses = expenses
        .where((expense) => expense.expenseDate.toLocal().isBefore(tomorrow))
        .toList();

    DateTime? firstDate;

    for (final expense in recordedExpenses) {
      final date = expense.expenseDate.toLocal();

      if (firstDate == null || date.isBefore(firstDate)) {
        firstDate = date;
      }
    }

    final monthlyTotals = <DateTime, int>{};

    if (firstDate != null) {
      var cursor = DateTime(firstDate.year, firstDate.month);
      final currentMonth = DateTime(today.year, today.month);

      while (!cursor.isAfter(currentMonth)) {
        monthlyTotals[cursor] = 0;
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
    }

    return SpendingPeriodSummary._calculate(
      expenses: recordedExpenses,
      start: firstDate,
      endExclusive: tomorrow,
      monthlyTotals: monthlyTotals,
    );
  }

  static SpendingPeriodSummary _calculate({
    required List<Expense> expenses,
    required DateTime? start,
    required DateTime endExclusive,
    required Map<DateTime, int> monthlyTotals,
  }) {
    var totalMinor = 0;
    var expenseCount = 0;
    DateTime? firstExpenseDate;
    final categoryTotals = <String, int>{};

    for (final expense in expenses) {
      final date = expense.expenseDate.toLocal();

      if (start != null && date.isBefore(start)) continue;
      if (!date.isBefore(endExclusive)) continue;

      final month = DateTime(date.year, date.month);

      // Excludes dates outside the displayed period.
      if (!monthlyTotals.containsKey(month)) continue;

      totalMinor += expense.amountMinor;
      expenseCount++;

      monthlyTotals.update(month, (amount) => amount + expense.amountMinor);

      categoryTotals.update(
        expense.categoryId,
        (amount) => amount + expense.amountMinor,
        ifAbsent: () => expense.amountMinor,
      );

      if (firstExpenseDate == null || date.isBefore(firstExpenseDate)) {
        firstExpenseDate = date;
      }
    }

    return SpendingPeriodSummary._(
      totalMinor: totalMinor,
      expenseCount: expenseCount,
      firstExpenseDate: firstExpenseDate,
      monthlyTotalsMinor: monthlyTotals,
      categoryTotalsMinor: categoryTotals,
    );
  }
}
