import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../models/monthly_expense_summary.dart';
import '../services/category_service.dart';

class SpendingCharts extends StatefulWidget {
  final String userId;
  final MonthlyExpenseSummary summary;

  const SpendingCharts({
    super.key,
    required this.userId,
    required this.summary,
  });

  @override
  State<SpendingCharts> createState() => _SpendingChartsState();
}

class _SpendingChartsState extends State<SpendingCharts> {
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

  Color _categoryColor(String categoryId) {
    const palette = [
      Color(0xFF7C4DFF),
      Color(0xFF00897B),
      Color(0xFFEF6C00),
      Color(0xFFEC407A),
      Color(0xFF1E88E5),
      Color(0xFF8E24AA),
      Color(0xFF689F38),
      Color(0xFF795548),
    ];

    var hash = 0;

    for (final character in categoryId.codeUnits) {
      hash = (hash * 31 + character) % palette.length;
    }

    return palette[hash];
  }

  Widget _chartCard({required String title, required Widget child}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _categoryChart() {
    final summary = widget.summary;

    final entries = summary.categoryTotalsMinor.entries.toList()
      ..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);

        return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
      });

    return _chartCard(
      title: 'Spending by category',
      child: StreamBuilder<List<ExpenseCategory>>(
        stream: _categoriesStream,
        builder: (context, snapshot) {
          final names = {
            for (final category in snapshot.data ?? <ExpenseCategory>[])
              category.id: category.name,
          };

          String label(String id) {
            if (names.containsKey(id)) return names[id]!;

            if (snapshot.hasError) return 'Category name unavailable';

            if (!snapshot.hasData) return 'Loading category…';

            return 'Unknown category';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label:
                    'Category spending chart. '
                    'Exact amounts are listed below.',
                child: SizedBox(
                  height: 220,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 58,
                      sectionsSpace: 3,
                      sections: [
                        for (final entry in entries)
                          PieChartSectionData(
                            value: entry.value.toDouble(),
                            color: _categoryColor(entry.key),
                            radius: 40,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: _categoryColor(entry.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(label(entry.key))),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _money(entry.value),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${(entry.value / summary.totalMinor * 100).toStringAsFixed(1)}%',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (snapshot.hasError)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Category names could not be loaded. '
                    'Spending amounts are still shown.',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dailyChart() {
    final summary = widget.summary;
    final colors = Theme.of(context).colorScheme;

    final spots = [
      for (final entry in summary.dailyTotalsMinor.entries)
        FlSpot(entry.key.toDouble(), entry.value / 100),
    ];

    final highest = spots.fold<double>(
      0,
      (maximum, spot) => spot.y > maximum ? spot.y : maximum,
    );

    final maximumY = highest == 0 ? 1.0 : highest * 1.2;

    return _chartCard(
      title: 'Daily spending',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Amount in LKR • touch a point for details'),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minX: 1,
                maxX: summary.dailyTotalsMinor.length.toDouble(),
                minY: 0,
                maxY: maximumY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maximumY / 4,
                ),
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
                    axisNameWidget: const Text('Day of month'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 7,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            value.toInt().toString(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final day = spot.x.round();
                        final minor = summary.dailyTotalsMinor[day] ?? 0;

                        return LineTooltipItem(
                          'Day $day\n${_money(minor)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: colors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Shows recorded spending for each calendar day. '
            'Days without recorded expenses appear as zero.',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summary.totalMinor == 0) {
      return _chartCard(
        title: 'Spending charts',
        child: const Text(
          'Add an expense in this month to see your spending charts.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_categoryChart(), const SizedBox(height: 16), _dailyChart()],
    );
  }
}
