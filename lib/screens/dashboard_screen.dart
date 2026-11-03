import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/monthly_budget.dart';
import '../models/monthly_expense_summary.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';

class DashboardScreen extends StatefulWidget {
  final String userId;

  const DashboardScreen({super.key, required this.userId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _month;
  late final BudgetService _budgetService;
  late final Stream<List<Expense>> _expensesStream;
  late Stream<MonthlyBudget?> _budgetStream;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _month = DateTime(now.year, now.month);

    _budgetService = BudgetService(userId: widget.userId);
    _budgetStream = _budgetService.watchBudget(_month);
    _expensesStream = ExpenseService(userId: widget.userId).watchExpenses();
  }

  String _money(int amountMinor) {
    final absolute = amountMinor.abs();
    final rupees = absolute ~/ 100;
    final cents = (absolute % 100).toString().padLeft(2, '0');
    final sign = amountMinor < 0 ? '-' : '';

    return '${sign}Rs. $rupees.$cents';
  }

  String _monthLabel(DateTime month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${names[month.month - 1]} ${month.year}';
  }

  void _selectMonth(DateTime month) {
    if (month.year < 2000 || month.year > 9999) return;

    final selected = DateTime(month.year, month.month);
    if (selected == _month) return;

    setState(() {
      _month = selected;
      _budgetStream = _budgetService.watchBudget(selected);
    });
  }

  Widget _statCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  String _comparisonText(MonthlyExpenseSummary summary) {
    final change = summary.changePercent;

    if (change == null) {
      return summary.totalMinor == 0
          ? 'No spending in either month.'
          : 'No previous-month spending to calculate a percentage.';
    }

    if (change == 0) {
      return 'Same spending as the previous month.';
    }

    final direction = change > 0 ? 'higher' : 'lower';

    return '${change.abs().toStringAsFixed(1)}% $direction '
        'than the previous month.';
  }

  Widget _budgetCard(MonthlyExpenseSummary summary) {
    return StreamBuilder<MonthlyBudget?>(
      key: ValueKey(MonthlyBudget.monthKey(_month)),
      stream: _budgetStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Could not load the monthly budget.'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final budget = snapshot.data;

        if (budget == null || budget.overallLimitMinor <= 0) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No budget set for this month. '
                'Use Monthly Budget to set a spending target.',
              ),
            ),
          );
        }

        final limit = budget.overallLimitMinor;
        final spent = summary.totalMinor;
        final remaining = limit - spent;
        final progress = spent / limit;

        final colors = Theme.of(context).colorScheme;
        final color = spent >= limit
            ? colors.error
            : spent * 100 >= limit * 80
            ? Colors.orange
            : colors.primary;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly budget',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  remaining < 0
                      ? '${_money(remaining.abs())} over budget'
                      : '${_money(remaining)} remaining',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('${_money(spent)} spent of ${_money(limit)}'),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0).toDouble(),
                  minHeight: 10,
                  color: color,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
                const SizedBox(height: 8),
                Text('${(progress * 100).toStringAsFixed(1)}% used'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboard(List<Expense> expenses) {
    final summary = MonthlyExpenseSummary.fromExpenses(
      expenses: expenses,
      month: _month,
    );

    final previousMonth = DateTime(_month.year, _month.month - 1);
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    final cards = [
      _statCard(
        title: 'Total spending',
        value: _money(summary.totalMinor),
        subtitle: '${summary.expenseCount} expenses',
        icon: Icons.payments_outlined,
      ),
      _statCard(
        title: 'Daily average',
        value: _money(summary.averageDailyMinor),
        subtitle: isCurrentMonth
            ? 'Across ${summary.averageDayCount} days through today'
            : 'Across ${summary.averageDayCount} calendar days',
        icon: Icons.calendar_today_outlined,
      ),
      _statCard(
        title: 'Previous month',
        value: _money(summary.previousMonthTotalMinor),
        subtitle: 'Full month: ${_monthLabel(previousMonth)}',
        icon: Icons.history,
      ),
      _statCard(
        title: 'Categories used',
        value: '${summary.categoryTotalsMinor.length}',
        subtitle: 'Categories with expenses in this month',
        icon: Icons.category_outlined,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: _month.year == 2000 && _month.month == 1
                  ? null
                  : () => _selectMonth(DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _monthLabel(_month),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: _month.year == 9999 && _month.month == 12
                  ? null
                  : () => _selectMonth(DateTime(_month.year, _month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => _selectMonth(DateTime.now()),
            icon: const Icon(Icons.today_outlined),
            label: const Text('Current month'),
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 600 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spending comparison',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(_comparisonText(summary)),
                const SizedBox(height: 8),
                const Text(
                  'Compares the selected month’s recorded spending '
                  'with the full previous month. '
                  'An unfinished month is a partial-period comparison.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _budgetCard(summary),
        if (summary.expenseCount == 0) ...[
          const SizedBox(height: 20),
          const Text('No expenses recorded for this month.'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: StreamBuilder<List<Expense>>(
              stream: _expensesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Could not load your expenses. '
                      'Check your connection and reopen this screen.',
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                return _buildDashboard(snapshot.data!);
              },
            ),
          ),
        ),
      ),
    );
  }
}
