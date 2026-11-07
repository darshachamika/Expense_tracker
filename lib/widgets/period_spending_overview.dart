import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../models/spending_period_summary.dart';
import '../services/category_service.dart';
import 'flow_doughnut_chart.dart';

class PeriodSpendingOverview extends StatefulWidget {
  final Stream<List<ExpenseCategory>>? categoriesStream;
  final String userId;
  final SpendingPeriodSummary summary;
  final ValueChanged<DateTime> onMonthSelected;

  const PeriodSpendingOverview({
    super.key,
    required this.userId,
    required this.summary,
    required this.onMonthSelected,
    this.categoriesStream,
  });

  @override
  State<PeriodSpendingOverview> createState() => _PeriodSpendingOverviewState();
}

class _PeriodSpendingOverviewState extends State<PeriodSpendingOverview> {
  late final Stream<List<ExpenseCategory>> _categoriesStream;

  @override
  void initState() {
    super.initState();

    _categoriesStream =
        widget.categoriesStream ??
        CategoryService(userId: widget.userId).watchCategories();
  }

  String _money(int minor) {
    return 'Rs. ${minor ~/ 100}.'
        '${(minor % 100).toString().padLeft(2, '0')}';
  }

  String _monthLabel(DateTime month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${names[month.month - 1]} ${month.year}';
  }

  Widget _panel(String title, List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyChart() {
    final entries = widget.summary.monthlyTotalsMinor.entries.toList();
    final byYear = <int, int>{};
    for (final entry in entries) {
      byYear.update(
        entry.key.year,
        (v) => v + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    final grouped = entries.length > 12;
    return _panel(grouped ? 'Spending by year' : 'Spending by month', [
      Text(
        grouped
            ? 'Each ring segment represents one year. Exact monthly amounts remain below.'
            : 'Tap a ring segment to explore its share. Select a month below to open its expenses.',
      ),
      const SizedBox(height: 16),
      FlowDoughnutChart(
        key: ValueKey('months-${entries.map((e) => e.key).join()}'),
        entries: grouped
            ? [
                for (final entry in byYear.entries)
                  FlowDoughnutEntry('${entry.key}', entry.value),
              ]
            : [
                for (final entry in entries)
                  FlowDoughnutEntry(
                    _monthLabel(entry.key),
                    entry.value,
                    onOpen: () => widget.onMonthSelected(entry.key),
                  ),
              ],
      ),
      const SizedBox(height: 12),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Exact monthly amounts'),
        children: [
          for (final entry in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_monthLabel(entry.key)),
              subtitle: Text(_money(entry.value)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onMonthSelected(entry.key),
            ),
        ],
      ),
    ]);
  }

  Widget _categoryBreakdown() {
    final entries = widget.summary.categoryTotalsMinor.entries.toList()
      ..sort((a, b) {
        final amount = b.value.compareTo(a.value);
        return amount != 0 ? amount : a.key.compareTo(b.key);
      });
    return _panel('Spending by category', [
      StreamBuilder<List<ExpenseCategory>>(
        stream: _categoriesStream,
        builder: (context, snapshot) {
          final names = {
            for (final category in snapshot.data ?? <ExpenseCategory>[])
              category.id: category.name,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowDoughnutChart(
                entries: [
                  for (final entry in entries)
                    FlowDoughnutEntry(
                      names[entry.key] ??
                          (snapshot.hasError
                              ? 'Category unavailable'
                              : snapshot.hasData
                              ? 'Unknown category'
                              : 'Loading category…'),
                      entry.value,
                    ),
                ],
              ),
              if (snapshot.hasError)
                const Text(
                  'Category names could not load. Recorded amounts are still shown.',
                ),
            ],
          );
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final highestMonth = summary.highestSpendingMonth;
    final firstDate = summary.firstExpenseDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel('Spending overview', [
          _row('Total spending', _money(summary.totalMinor)),
          _row('Expenses', '${summary.expenseCount}'),
          _row('Monthly average', _money(summary.averageMonthlyMinor)),
          _row('Months covered', '${summary.monthCount}'),
          _row(
            'Highest spending month',
            highestMonth == null ? 'None' : _monthLabel(highestMonth),
          ),
          if (firstDate != null)
            _row(
              'First expense in this period',
              '${firstDate.year}-'
                  '${firstDate.month.toString().padLeft(2, '0')}-'
                  '${firstDate.day.toString().padLeft(2, '0')}',
            ),
          const SizedBox(height: 8),
          const Text(
            'Monthly average includes months with no spending. '
            'The current month is still in progress.',
          ),
        ]),
        const SizedBox(height: 16),
        if (summary.monthCount > 0) _monthlyChart(),
        if (summary.totalMinor > 0) ...[
          const SizedBox(height: 16),
          _categoryBreakdown(),
        ] else ...[
          const SizedBox(height: 16),
          const Text('No expenses recorded in this period.'),
        ],
      ],
    );
  }
}
