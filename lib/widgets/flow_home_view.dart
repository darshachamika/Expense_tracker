import 'package:flutter/material.dart';

import '../models/flow_profile.dart';
import '../screens/profile_screen.dart';
import '../models/expense.dart';
import '../models/monthly_budget.dart';
import '../models/monthly_expense_summary.dart';
import '../theme/flow_theme.dart';
import 'flow_format.dart';
import 'flow_visuals.dart';

/// Presentation-only aggregation. Amounts remain integer minor units.
List<({DateTime date, int amountMinor})> flowWeek(
  List<Expense> expenses,
  DateTime month,
  DateTime now,
) {
  final end = month.year == now.year && month.month == now.month
      ? DateTime(now.year, now.month, now.day)
      : DateTime(month.year, month.month + 1, 0);
  return List.generate(7, (index) {
    final date = DateTime(end.year, end.month, end.day - 6 + index);
    final total = expenses
        .where((expense) {
          final local = expense.expenseDate.toLocal();
          return local.year == date.year &&
              local.month == date.month &&
              local.day == date.day;
        })
        .fold<int>(0, (sum, expense) => sum + expense.amountMinor);
    return (date: date, amountMinor: total);
  });
}

class FlowHomeView extends StatelessWidget {
  final FlowProfile profile;
  final Widget? planPreview;
  final VoidCallback? onProfile,
      onCustomize,
      onAdd,
      onBudget,
      onBills,
      onGoals,
      onAdvisor;
  final List<Expense> expenses;
  final DateTime month;
  final DateTime now;
  final MonthlyBudget? budget;
  final bool budgetLoading;
  final bool budgetError;
  final String? displayName;
  final String? photoUrl;
  final String Function(String) categoryLabel;
  final ValueChanged<DateTime> onMonth;
  final VoidCallback? onActivity;
  final VoidCallback onAnalytics;
  final ValueChanged<Expense>? onExpense;

  const FlowHomeView({
    super.key,
    required this.expenses,
    this.profile = const FlowProfile(),
    this.planPreview,
    this.onProfile,
    this.onCustomize,
    this.onAdd,
    this.onBudget,
    this.onBills,
    this.onGoals,
    this.onAdvisor,
    required this.month,
    required this.now,
    this.budget,
    this.budgetLoading = false,
    this.budgetError = false,
    this.displayName,
    this.photoUrl,
    required this.categoryLabel,
    required this.onMonth,
    this.onActivity,
    required this.onAnalytics,
    this.onExpense,
  });

  @override
  Widget build(BuildContext context) {
    final summary = MonthlyExpenseSummary.fromExpenses(
      expenses: expenses,
      month: month,
      now: now,
    );
    final current = month.year == now.year && month.month == now.month;
    final name = displayName?.trim().split(RegExp(r'\s+')).firstOrNull;
    final recent = expenses.where((e) {
      final date = e.expenseDate.toLocal();
      return date.year == month.year && date.month == month.month;
    }).toList()..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    final change = summary.changePercent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${FlowFormat.greeting(now)}${name == null || name.isEmpty ? '' : ', $name'}',
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'My profile',
              onPressed: onProfile,
              icon: ProfileAvatar(
                profile: profile,
                fallbackUrl: photoUrl,
                radius: 23,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              size: 17,
              color: FlowTheme.blue,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                FlowFormat.month(month),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Previous month',
              onPressed: month.year <= 2000 && month.month == 1
                  ? null
                  : () => onMonth(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Next month',
              onPressed: month.year >= 9999 && month.month == 12
                  ? null
                  : () => onMonth(DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FlowLiquidCard(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current
                    ? 'Spent this month'
                    : 'Spending in ${FlowFormat.month(month)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                FlowFormat.money(summary.totalMinor),
                key: const ValueKey('flow-home-total'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 34,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  change == null
                      ? '${summary.expenseCount} recorded expenses'
                      : '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}% vs full previous month',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _budgetTiles(summary),
        const SizedBox(height: 14),
        if (onAdd != null) _shortcuts(),
        for (final section in profile.order.where(
          (s) => !profile.hidden.contains(s),
        )) ...[
          if (section == 'weekly')
            FlowWeekChart(entries: flowWeek(expenses, month, now)),
          if (section == 'categories') _categories(recent),
          if (section == 'plans' && planPreview != null) planPreview!,
          if (section == 'insights')
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome, color: FlowTheme.blue),
                title: const Text('Ripple insights'),
                subtitle: Text(_insight(summary)),
                trailing: const Icon(Icons.chevron_right),
                onTap: onAdvisor,
              ),
            ),
          if (section == 'recent')
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent activity',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onActivity != null)
                      TextButton(
                        onPressed: onActivity,
                        child: const Text('See all ›'),
                      ),
                  ],
                ),
                if (recent.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No expenses in this month. Tap + to add your first expense.',
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < recent.take(3).length; i++) ...[
                          FlowExpenseRow(
                            expense: recent[i],
                            categoryLabel: categoryLabel(recent[i].categoryId),
                            onTap:
                                onExpense == null ||
                                    recent[i].id.startsWith('bill_')
                                ? null
                                : () => onExpense!(recent[i]),
                          ),
                          if (i < recent.take(3).length - 1)
                            const Divider(height: 1, indent: 68, endIndent: 14),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAnalytics,
            icon: const Icon(Icons.insights_outlined),
            label: const Text('Month, year & all-time insights'),
          ),
        ),
        if (!current)
          TextButton(
            onPressed: () => onMonth(DateTime(now.year, now.month)),
            child: const Text('Back to current month'),
          ),
      ],
    );
  }

  Widget _shortcuts() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        for (final action
            in <({String label, IconData icon, VoidCallback? tap})>[
              (label: 'Add', icon: Icons.add, tap: onAdd),
              (label: 'Budgets', icon: Icons.layers_outlined, tap: onBudget),
              (label: 'Bills', icon: Icons.receipt_long_outlined, tap: onBills),
              (label: 'Goals', icon: Icons.flag_outlined, tap: onGoals),
            ])
          Expanded(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: action.tap,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Icon(action.icon, color: FlowTheme.blue),
                      const SizedBox(height: 8),
                      Text(
                        action.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  String _insight(MonthlyExpenseSummary summary) {
    final limit = budget?.overallLimitMinor ?? 0;
    if (limit > 0 && summary.totalMinor > limit)
      return 'You are ${FlowFormat.money(summary.totalMinor - limit)} over your monthly budget.';
    if (limit > 0)
      return '${FlowFormat.money(limit - summary.totalMinor)} left in your monthly budget. Explore your plan with Ripple.';
    return summary.expenseCount == 0
        ? 'Add an expense to start understanding your spending.'
        : 'Explore your spending patterns with Ripple.';
  }

  Widget _categories(List<Expense> expenses) {
    final totals = <String, int>{};
    for (final expense in expenses) {
      totals.update(
        expense.categoryId,
        (v) => v + expense.amountMinor,
        ifAbsent: () => expense.amountMinor,
      );
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = expenses.fold<int>(0, (sum, e) => sum + e.amountMinor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'By category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Your category breakdown will appear here.'),
              ),
            for (final entry in entries.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            categoryLabel(entry.key),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${FlowFormat.money(entry.value)} • ${total == 0 ? 0 : (entry.value * 100 / total).round()}%',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : entry.value / total,
                      minHeight: 6,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _budgetTiles(MonthlyExpenseSummary summary) {
    final limit = budget?.overallLimitMinor ?? 0;
    final valid = limit > 0;
    final remaining = limit - summary.totalMinor;
    final label = budgetLoading
        ? 'Loading…'
        : budgetError
        ? 'Unavailable'
        : valid
        ? FlowFormat.money(limit)
        : 'Not set';
    final value = budgetLoading
        ? 'Loading…'
        : budgetError
        ? 'Unavailable'
        : valid
        ? FlowFormat.money(remaining.abs())
        : 'Set a budget';
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        final tiles = [
          _mini(
            'Monthly budget',
            label,
            Icons.account_balance_wallet_outlined,
            const Color(0xFFE0EDFF),
            FlowTheme.blue,
          ),
          _mini(
            valid && remaining < 0 ? 'Over budget' : 'Remaining',
            value,
            Icons.donut_large_rounded,
            const Color(0xFFD6F8F1),
            const Color(0xFF008879),
          ),
        ];
        if (narrow)
          return Column(
            children: [tiles[0], const SizedBox(height: 10), tiles[1]],
          );
        return Row(
          children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 10),
            Expanded(child: tiles[1]),
          ],
        );
      },
    );
  }

  Widget _mini(
    String label,
    String value,
    IconData icon,
    Color background,
    Color color,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(19),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: FlowTheme.ink),
      child: Row(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class FlowWeekChart extends StatelessWidget {
  final List<({DateTime date, int amountMinor})> entries;
  const FlowWeekChart({super.key, required this.entries});
  @override
  Widget build(BuildContext context) {
    final max = entries.fold<int>(
      0,
      (result, entry) =>
          entry.amountMinor > result ? entry.amountMinor : result,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weekly spending',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${FlowFormat.shortDate(entries.first.date)} – ${FlowFormat.shortDate(entries.last.date)} • LKR',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 145,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in entries)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${FlowFormat.shortDate(entry.date)}: ${FlowFormat.money(entry.amountMinor)}',
                        child: Semantics(
                          label:
                              '${FlowFormat.shortDate(entry.date)}, ${FlowFormat.money(entry.amountMinor)}',
                          child: ExcludeSemantics(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 20,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        FlowFormat.money(entry.amountMinor),
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: FractionallySizedBox(
                                        heightFactor: max == 0
                                            ? .025
                                            : (entry.amountMinor / max)
                                                  .clamp(.025, 1.0)
                                                  .toDouble(),
                                        widthFactor: .76,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: entry.amountMinor == 0
                                                  ? [
                                                      const Color(0xFFE5EDF8),
                                                      const Color(0xFFE5EDF8),
                                                    ]
                                                  : [
                                                      FlowTheme.aqua,
                                                      FlowTheme.blue,
                                                    ],
                                            ),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(7),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    FlowFormat.weekdays[entry.date.weekday - 1],
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  Text(
                                    '${entry.date.day}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (max == 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No recorded spending in these seven days.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FlowExpenseRow extends StatelessWidget {
  final Expense expense;
  final String categoryLabel;
  final VoidCallback? onTap;
  final Widget? actions;
  const FlowExpenseRow({
    super.key,
    required this.expense,
    required this.categoryLabel,
    this.onTap,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          FlowCategoryIcon(category: categoryLabel),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  expense.id.startsWith('bill_')
                      ? '$categoryLabel • Bill payment'
                      : categoryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width < 360 ? 86 : 125,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FlowFormat.money(expense.amountMinor),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    expense.paymentMethod,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (actions != null) actions!,
        ],
      ),
    ),
  );
}
