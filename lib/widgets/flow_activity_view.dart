import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/expense_category.dart';
import '../theme/flow_theme.dart';
import 'flow_format.dart';
import 'flow_home_view.dart';
import 'flow_visuals.dart';

class FlowActivityView extends StatelessWidget {
  final List<Expense> expenses;
  final List<ExpenseCategory> categories;
  final String? selectedCategory;
  final String periodLabel;
  final String dateFilterLabel;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategory;
  final VoidCallback onFilters;
  final VoidCallback onClear;
  final ValueChanged<Expense> onEdit;
  final ValueChanged<Expense> onDelete;
  final String Function(String) categoryLabel;
  final bool busy;
  final DateTime now;
  const FlowActivityView({
    super.key,
    required this.expenses,
    required this.categories,
    this.selectedCategory,
    required this.periodLabel,
    required this.dateFilterLabel,
    required this.searchController,
    required this.onSearch,
    required this.onCategory,
    required this.onFilters,
    required this.onClear,
    required this.onEdit,
    required this.onDelete,
    required this.categoryLabel,
    this.busy = false,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...expenses]
      ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    final groups = <DateTime, List<Expense>>{};
    for (final expense in sorted) {
      final date = DateUtils.dateOnly(expense.expenseDate.toLocal());
      (groups[date] ??= []).add(expense);
    }
    final total = expenses.fold<int>(0, (sum, item) => sum + item.amountMinor);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                onChanged: onSearch,
                decoration: const InputDecoration(
                  hintText: 'Search transactions',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onFilters,
              tooltip: 'Filter dates and transactions',
              icon: const Icon(Icons.filter_alt_outlined),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  selectedColor: FlowTheme.blue,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selectedCategory == null
                        ? Colors.white
                        : FlowTheme.ink,
                  ),
                  label: const Text('All'),
                  selected: selectedCategory == null,
                  onSelected: (_) => onCategory(null),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    selectedColor: FlowTheme.blue,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selectedCategory == category.id
                          ? Colors.white
                          : FlowTheme.ink,
                    ),
                    avatar: SizedBox(
                      width: 22,
                      height: 22,
                      child: FittedBox(
                        child: FlowCategoryIcon(category: category.name),
                      ),
                    ),
                    label: Text(
                      category.archived
                          ? '${category.name} (Archived)'
                          : category.name,
                    ),
                    selected: selectedCategory == category.id,
                    onSelected: (_) => onCategory(category.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                dateFilterLabel,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
        FlowLiquidCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                periodLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                FlowFormat.money(total),
                key: const ValueKey('flow-activity-total'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${expenses.length} transactions',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (groups.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 36,
                    color: FlowTheme.blue,
                  ),
                  const SizedBox(height: 12),
                  const Text('No transactions in this view.'),
                  TextButton(
                    onPressed: onClear,
                    child: const Text('Show all recorded expenses'),
                  ),
                ],
              ),
            ),
          ),
        for (final entry in groups.entries) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                FlowFormat.dateGroup(entry.key, now),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Total: ${FlowFormat.money(entry.value.fold<int>(0, (sum, item) => sum + item.amountMinor))}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  FlowExpenseRow(
                    expense: entry.value[i],
                    categoryLabel: categoryLabel(entry.value[i].categoryId),
                    onTap: busy || entry.value[i].id.startsWith('bill_')
                        ? null
                        : () => onEdit(entry.value[i]),
                    actions: entry.value[i].id.startsWith('bill_')
                        ? const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Tooltip(
                              message: 'Manage this payment from Bills',
                              child: Icon(Icons.lock_outline, size: 17),
                            ),
                          )
                        : SizedBox(
                            width: 32,
                            child: PopupMenuButton<String>(
                              enabled: !busy,
                              padding: EdgeInsets.zero,
                              tooltip: 'Expense actions',
                              onSelected: (value) => value == 'edit'
                                  ? onEdit(entry.value[i])
                                  : onDelete(entry.value[i]),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (i < entry.value.length - 1)
                    const Divider(height: 1, indent: 68, endIndent: 12),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
