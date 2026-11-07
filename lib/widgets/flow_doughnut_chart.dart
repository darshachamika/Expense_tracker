import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'flow_format.dart';

class FlowDoughnutEntry {
  final String label;
  final int amountMinor;
  final VoidCallback? onOpen;
  const FlowDoughnutEntry(this.label, this.amountMinor, {this.onOpen});
}

class FlowDoughnutChart extends StatefulWidget {
  final List<FlowDoughnutEntry> entries;
  const FlowDoughnutChart({super.key, required this.entries});
  @override
  State<FlowDoughnutChart> createState() => _FlowDoughnutChartState();
}

class _FlowDoughnutChartState extends State<FlowDoughnutChart> {
  String? _selectedLabel;
  static const _palette = [
    Color(0xFF058DFF),
    Color(0xFF00BDD7),
    Color(0xFF9278EF),
    Color(0xFFFFB75E),
    Color(0xFFEF80AE),
    Color(0xFF37BCB0),
    Color(0xFF6883D9),
    Color(0xFFE38B67),
    Color(0xFFBA83DB),
    Color(0xFF88BE54),
    Color(0xFF4AA9CB),
    Color(0xFFDFBD58),
  ];
  @override
  Widget build(BuildContext context) {
    final entries = widget.entries.where((e) => e.amountMinor > 0).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.amountMinor);
    final selected = entries
        .where((e) => e.label == _selectedLabel)
        .firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: 244,
            height: 244,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Semantics(
                  label:
                      'Spending doughnut. Exact amounts and percentages below.',
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 76,
                      sectionsSpace: 3,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          if (event is! FlTapUpEvent || entries.isEmpty) return;
                          final index =
                              response?.touchedSection?.touchedSectionIndex;
                          if (index != null &&
                              index >= 0 &&
                              index < entries.length)
                            setState(
                              () => _selectedLabel = entries[index].label,
                            );
                        },
                      ),
                      sections: entries.isEmpty
                          ? [
                              PieChartSectionData(
                                value: 1,
                                color: colors.surfaceContainerHighest,
                                radius: 34,
                                showTitle: false,
                              ),
                            ]
                          : [
                              for (var i = 0; i < entries.length; i++)
                                PieChartSectionData(
                                  value: entries[i].amountMinor.toDouble(),
                                  color: _palette[i % _palette.length],
                                  radius: entries[i] == selected ? 42 : 34,
                                  showTitle: false,
                                ),
                            ],
                    ),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                  ),
                ),
                IgnorePointer(
                  child: SizedBox(
                    width: 140,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selected?.label ??
                              (total == 0 ? 'No spending' : 'Total spending'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            FlowFormat.money(selected?.amountMinor ?? total),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (selected != null)
                          Text(
                            '${(selected.amountMinor / total * 100).toStringAsFixed(1)}%',
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (entries.isEmpty)
          const Text(
            'No recorded expenses in this period.',
            textAlign: TextAlign.center,
          ),
        if (selected != null)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _selectedLabel = null),
              child: const Text('Show total'),
            ),
          ),
        const SizedBox(height: 12),
        for (var i = 0; i < entries.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _palette[i % _palette.length],
              ),
            ),
            title: Text(entries[i].label),
            subtitle: Text(
              '${(entries[i].amountMinor / total * 100).toStringAsFixed(1)}% of spending',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  FlowFormat.money(entries[i].amountMinor),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (entries[i].onOpen != null)
                  const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap:
                entries[i].onOpen ??
                () => setState(() => _selectedLabel = entries[i].label),
          ),
      ],
    );
  }
}
