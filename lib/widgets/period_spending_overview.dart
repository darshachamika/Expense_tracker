import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../models/spending_period_summary.dart';
import '../services/category_service.dart';

class PeriodSpendingOverview extends StatefulWidget {
  final String userId;
  final SpendingPeriodSummary summary;
  final ValueChanged<DateTime> onMonthSelected;

  const PeriodSpendingOverview({
    super.key,
    required this.userId,
    required this.summary,
    required this.onMonthSelected,
  });

  @override
  State<PeriodSpendingOverview> createState() => _PeriodSpendingOverviewState();
}

class _PeriodSpendingOverviewState extends State<PeriodSpendingOverview> {
  late final Stream<List<ExpenseCategory>> _categoriesStream;

  @override
  void initState() {
    super.initState();

    _categoriesStream = CategoryService(userId: widget.userId)
        .watchCategories();
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
    final colors = Theme.of(context).colorScheme;

    final highest = entries.fold<int>(
      0,
      (maximum, entry) => entry.value > maximum ? entry.value : maximum,
    );

    final maxY = highest == 0 ? 1.0 : highest / 100 * 1.2;

    return _panel('Monthly spending', [
      const Text(
        'Amounts in LKR. Scroll sideways for more months. '
        'Tap a bar or month label to open that month.',
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, constraints) {
          final requiredWidth = entries.length * 64.0;
          final chartWidth = requiredWidth > constraints.maxWidth
              ? requiredWidth
              : constraints.maxWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              height: 260,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();

                          if (index < 0 || index >= entries.length) {
                            return const SizedBox.shrink();
                          }

                          return InkWell(
                            onTap: () =>
                                widget.onMonthSelected(entries[index].key),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _monthLabel(entries[index].key)
                                    .replaceFirst(' ', '\n'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;

                      final index = response?.spot?.touchedBarGroupIndex;

                      if (index == null ||
                          index < 0 ||
                          index >= entries.length) {
                        return;
                      }

                      widget.onMonthSelected(entries[index].key);
                    },
                    touchTooltipData: BarTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final entry = entries[groupIndex];

                        return BarTooltipItem(
                          '${_monthLabel(entry.key)}\n${_money(entry.value)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (var index = 0; index < entries.length; index++)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: entries[index].value / 100,
                            width: 22,
                            color: colors.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
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
    final summary = widget.summary;

    final entries = summary.categoryTotalsMinor.entries.toList()
      ..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);
        return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
      });

    return _panel('Category breakdown', [
      StreamBuilder<List<ExpenseCategory>>(
        stream: _categoriesStream,
        builder: (context, snapshot) {
          final names = {
            for (final category in snapshot.data ?? <ExpenseCategory>[])
              category.id: category.name,
          };

          return Column(
            children: [
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    names[entry.key] ??
                        (snapshot.hasData
                            ? 'Unknown category'
                            : snapshot.hasError
                            ? 'Category name unavailable'
                            : 'Loading category…'),
                  ),
                  subtitle: Text(
                    '${(entry.value / summary.totalMinor * 100).toStringAsFixed(1)}% of spending',
                  ),
                  trailing: Text(_money(entry.value)),
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
