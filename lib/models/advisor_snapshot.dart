import 'expense.dart';
import 'expense_category.dart';
import 'monthly_budget.dart';
import 'monthly_expense_summary.dart';
import 'planned_bill.dart';
import 'savings_goal.dart';

String advisorMoney(int minor) {
  final value = minor.abs();
  return '${minor < 0 ? '-' : ''}Rs. ${value ~/ 100}.'
      '${(value % 100).toString().padLeft(2, '0')}';
}

String advisorDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// A local calculation result. No Firestore writes or model calls happen here.
class AdvisorSnapshot {
  final DateTime capturedAt;
  final MonthlyExpenseSummary summary;
  final MonthlyBudget? budget;
  final int pendingBillsMinor;
  final int overdueBillsMinor;
  final int activeGoalCount;
  final Map<String, Object?> _payload;

  const AdvisorSnapshot._({
    required this.capturedAt,
    required this.summary,
    required this.budget,
    required this.pendingBillsMinor,
    required this.overdueBillsMinor,
    required this.activeGoalCount,
    required Map<String, Object?> payload,
  }) : _payload = payload;

  int? get remainingMinor =>
      budget == null ? null : budget!.overallLimitMinor - summary.totalMinor;

  int? get remainingAfterBillsMinor =>
      remainingMinor == null ? null : remainingMinor! - pendingBillsMinor;

  Map<String, Object?> toPromptData() => Map.unmodifiable(_payload);

  factory AdvisorSnapshot.calculate({
    required DateTime now,
    required List<Expense> expenses,
    required List<ExpenseCategory> categories,
    required List<PlannedBill> bills,
    required List<SavingsGoal> goals,
    required Map<String, int> savedByGoal,
    MonthlyBudget? budget,
  }) {
    final localNow = now.toLocal();
    final month = DateTime(localNow.year, localNow.month);
    final nextMonth = DateTime(localNow.year, localNow.month + 1);
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    if (budget != null && budget.id != MonthlyBudget.monthKey(month)) {
      throw ArgumentError('Budget must match the current month.');
    }
    final summary = MonthlyExpenseSummary.fromExpenses(
      expenses: expenses,
      month: month,
      now: localNow,
    );
    final byId = {for (final category in categories) category.id: category};
    final categoryIds =
        {
          ...summary.categoryTotalsMinor.keys,
          ...?budget?.categoryLimitsMinor.keys,
        }.toList()..sort((a, b) {
          final order = (summary.categoryTotalsMinor[b] ?? 0).compareTo(
            summary.categoryTotalsMinor[a] ?? 0,
          );
          return order == 0 ? a.compareTo(b) : order;
        });
    // Local IDs make unknown/duplicate labels distinguishable without sending
    // actual Firestore document IDs to the model.
    final categoryRows = <Map<String, Object?>>[];
    for (var index = 0; index < categoryIds.length; index++) {
      final id = categoryIds[index];
      final category = byId[id];
      final spent = summary.categoryTotalsMinor[id] ?? 0;
      final limit = budget?.categoryLimitsMinor[id];
      categoryRows.add({
        'reference': 'category_${index + 1}',
        'name': category?.name ?? 'Unknown category ${index + 1}',
        'archived': category?.archived,
        'spent': advisorMoney(spent),
        'limit': limit == null ? null : advisorMoney(limit),
        'remaining': limit == null ? null : advisorMoney(limit - spent),
      });
    }
    final pending =
        bills
            .where(
              (bill) =>
                  !bill.isPaid && bill.dueDate.toLocal().isBefore(nextMonth),
            )
            .toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    var pendingMinor = 0;
    var overdueMinor = 0;
    for (final bill in pending) {
      pendingMinor += bill.amountMinor;
      if (bill.dueDate.toLocal().isBefore(today)) {
        overdueMinor += bill.amountMinor;
      }
    }
    final goalRows = <Map<String, Object?>>[];
    for (final goal in goals.where((goal) => !goal.archived)) {
      final saved = savedByGoal[goal.id];
      // Missing data is never treated as zero savings.
      if (saved == null) throw StateError('Savings contributions are missing.');
      final monthly = goal.monthlyRequiredMinor(
        savedMinor: saved,
        now: localNow,
      );
      goalRows.add({
        'name': goal.title,
        'target': advisorMoney(goal.targetMinor),
        'saved': advisorMoney(saved),
        'remaining': advisorMoney(goal.remainingMinor(saved)),
        'progressPercent': (goal.progress(saved) * 100).toStringAsFixed(1),
        'completed': goal.isCompleted(saved),
        'targetDate': goal.targetDate == null
            ? null
            : advisorDate(goal.targetDate!),
        'monthlyRequired': monthly == null ? null : advisorMoney(monthly),
      });
    }
    final remaining = budget == null
        ? null
        : budget.overallLimitMinor - summary.totalMinor;
    return AdvisorSnapshot._(
      capturedAt: localNow,
      summary: summary,
      budget: budget,
      pendingBillsMinor: pendingMinor,
      overdueBillsMinor: overdueMinor,
      activeGoalCount: goalRows.length,
      payload: {
        'capturedAtLocal': localNow.toIso8601String(),
        'month': MonthlyBudget.monthKey(month),
        'currency': 'LKR; amounts are preformatted rupees and cents',
        'scope':
            'Current calendar month and previous full calendar month. '
            'Reads are separate server requests, not one atomic snapshot. '
            'Only recorded bill occurrences are included; overdue unpaid '
            'occurrences before month-end are reserved. Active savings goals only. '
            'Savings contributions are separate from spending and not subtracted '
            'from the remaining budget. Bank balance and income are unknown.',
        'spending': advisorMoney(summary.totalMinor),
        'expenseCount': summary.expenseCount,
        'previousFullMonthSpending': advisorMoney(
          summary.previousMonthTotalMinor,
        ),
        'comparisonCaution':
            'Current month may be incomplete. Do not present '
            'this as a like-for-like full month comparison.',
        'monthlyBudget': budget == null
            ? null
            : advisorMoney(budget.overallLimitMinor),
        'remainingBudget': remaining == null ? null : advisorMoney(remaining),
        'pendingBillsDueByMonthEnd': advisorMoney(pendingMinor),
        'overdueBillsIncludedInPending': advisorMoney(overdueMinor),
        'remainingBudgetAfterBills': remaining == null
            ? null
            : advisorMoney(remaining - pendingMinor),
        'categoriesHighestSpendingFirst': categoryRows,
        'pendingBills': [
          for (final bill in pending)
            {
              'name': bill.title,
              'amount': advisorMoney(bill.amountMinor),
              'dueDate': advisorDate(bill.dueDate),
              'overdue': bill.dueDate.toLocal().isBefore(today),
            },
        ],
        'activeSavingsGoals': goalRows,
      },
    );
  }
}
