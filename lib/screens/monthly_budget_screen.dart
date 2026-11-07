import 'package:flutter/material.dart';
import '../widgets/flow_visuals.dart';
import '../widgets/flow_format.dart';

import '../models/expense.dart';
import '../models/monthly_budget.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../models/expense_category.dart';
import '../services/category_service.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final String userId;
  final VoidCallback? onOpenAdvisor;
  final ValueChanged<int>? onNavigate;

  const MonthlyBudgetScreen({super.key, required this.userId, this.onOpenAdvisor, this.onNavigate});

  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  late DateTime _month;
  late final BudgetService _budgetService;
  late Stream<MonthlyBudget?> _budgetStream;
  late final Stream<List<Expense>> _expensesStream;
  late final Stream<List<ExpenseCategory>> _categoriesStream;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _month = DateTime(now.year, now.month);

    _budgetService = BudgetService(userId: widget.userId);
    _budgetStream = _budgetService.watchBudget(_month);
    _expensesStream = ExpenseService(userId: widget.userId).watchExpenses();
    _categoriesStream = CategoryService(userId: widget.userId)
        .watchCategories();
  }

  String _money(int amountMinor) => FlowFormat.money(amountMinor);

  String get _monthLabel {
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

    return '${names[_month.month - 1]} ${_month.year}';
  }

  void _selectMonth(DateTime month) {
    if (_saving || month.year < 2000 || month.year > 9999) return;

    final selected = DateTime(month.year, month.month);
    if (selected == _month) return;

    setState(() {
      _month = selected;
      _budgetStream = _budgetService.watchBudget(selected);
    });
  }

  void _changeMonth(int offset) {
    _selectMonth(DateTime(_month.year, _month.month + offset));
  }

  void _goToCurrentMonth() {
    _selectMonth(DateTime.now());
  }

  Future<void> _editBudget(MonthlyBudget? currentBudget) async {
    if (_saving) return;

    final selectedMonth = _month;

    final amountMinor = await showDialog<int>(
      context: context,
      builder: (_) => _BudgetAmountDialog(
        initialAmountMinor: currentBudget?.overallLimitMinor,
      ),
    );

    if (amountMinor == null || !mounted) return;

    setState(() => _saving = true);

    try {
      await _budgetService.saveBudget(
        month: selectedMonth,
        overallLimitMinor: amountMinor,
        // Preserve category limits when changing the overall budget.
        categoryLimitsMinor: currentBudget?.categoryLimitsMinor ?? const {},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monthly budget saved.')));
    } catch (error, stackTrace) {
      debugPrint('Budget save failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the budget. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _changeCategoryLimit({
    required MonthlyBudget budget,
    required String categoryId,
    required String categoryName,
    bool remove = false,
  }) async {
    if (_saving) return;

    final selectedMonth = _month;
    int? amountMinor;

    if (!remove) {
      amountMinor = await showDialog<int>(
        context: context,
        builder: (_) => _BudgetAmountDialog(
          title: '$categoryName budget',
          initialAmountMinor: budget.categoryLimitsMinor[categoryId],
        ),
      );
      if (amountMinor == null || !mounted) return;
    }

    if (!mounted) return;

    final limits = Map<String, int>.from(budget.categoryLimitsMinor);
    if (remove) {
      limits.remove(categoryId);
    } else {
      limits[categoryId] = amountMinor!;
    }

    setState(() => _saving = true);
    try {
      await _budgetService.saveBudget(
        month: selectedMonth,
        overallLimitMinor: budget.overallLimitMinor,
        categoryLimitsMinor: limits,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remove ? 'Category limit removed.' : 'Category budget saved.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Category budget save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update the category budget. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildCategoryBudgets(
    MonthlyBudget budget,
    List<Expense> monthExpenses,
  ) {
    return StreamBuilder<List<ExpenseCategory>>(
      stream: _categoriesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Could not load categories. Reopen this screen to retry.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final categoriesById = {
          for (final category in snapshot.data!) category.id: category,
        };

        // Keep existing limits visible for archived or unavailable categories.
        final categoryIds = <String>{
          for (final category in snapshot.data!)
            if (!category.archived) category.id,
          ...budget.categoryLimitsMinor.keys,
        }.toList();

        String categoryLabel(String id) {
          final category = categoriesById[id];
          if (category == null) return 'Unavailable category ($id)';
          return category.archived
              ? '${category.name} (Archived)'
              : category.name;
        }

        categoryIds.sort(
          (a, b) =>
              categoryLabel(a)
                  .toLowerCase()
                  .compareTo(categoryLabel(b).toLowerCase()),
        );

        final spentByCategory = <String, int>{};
        for (final expense in monthExpenses) {
          spentByCategory.update(
            expense.categoryId,
            (amount) => amount + expense.amountMinor,
            ifAbsent: () => expense.amountMinor,
          );
        }

        if (categoryIds.isEmpty) {
          return const Text(
            'Create a category from the home screen to set category budgets.',
          );
        }

        final colors = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final categoryId in categoryIds)
              Builder(
                builder: (context) {
                  final name = categoryLabel(categoryId);
                  final category = categoriesById[categoryId];
                  final limit = budget.categoryLimitsMinor[categoryId];
                  final spent = spentByCategory[categoryId] ?? 0;
                  final hasLimit = limit != null && limit > 0;
                  final remaining = hasLimit ? limit - spent : 0;
                  final progress = hasLimit ? spent / limit : 0.0;
                  final color = hasLimit && spent >= limit
                      ? colors.error
                      : hasLimit && spent * 100 >= limit * 80
                      ? Colors.orange
                      : FlowCategoryIcon.colorFor(name);

                  String? warning;
                  if (hasLimit) {
                    if (spent > limit) {
                      warning = 'Over budget by ${_money(spent - limit)}.';
                    } else if (spent == limit) {
                      warning = 'Category budget fully used.';
                    } else if (spent * 100 >= limit * 80) {
                      warning = 'At least 80% of this category budget is used.';
                    }
                  }

                  final canSetLimit =
                      hasLimit || (category != null && !category.archived);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(borderRadius: BorderRadius.circular(22),
                      onTap: _saving || !canSetLimit ? null : () => _changeCategoryLimit(budget: budget, categoryId: categoryId, categoryName: name),
                      child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        FlowCategoryIcon(category: name), const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(hasLimit ? '${_money(spent)} / ${_money(limit)}' : '${_money(spent)} spent • No limit', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 10),
                          if (hasLimit) LinearProgressIndicator(value: progress.clamp(0.0, 1.0).toDouble(), minHeight: 7, color: color),
                          if (warning != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(warning, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
                          if (hasLimit && warning == null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${_money(remaining)} left', style: const TextStyle(fontSize: 11, color: Color(0xFF53627D)))),
                        ])),
                        SizedBox(width: 32, child: PopupMenuButton<String>(enabled: !_saving, padding: EdgeInsets.zero, tooltip: 'Category budget actions',
                          onSelected: (action) => _changeCategoryLimit(budget: budget, categoryId: categoryId, categoryName: name, remove: action == 'remove'),
                          itemBuilder: (_) => [
                            if (canSetLimit) PopupMenuItem(value: 'edit', child: Text(hasLimit ? 'Edit limit' : 'Set limit')),
                            if (hasLimit) const PopupMenuItem(value: 'remove', child: Text('Remove limit')),
                          ],
                        )),
                      ])),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildContent(MonthlyBudget? budget, List<Expense> allExpenses) {
    final nextMonth = DateTime(_month.year, _month.month + 1);

    final expenses = allExpenses.where((expense) {
      final date = expense.expenseDate.toLocal();

      return !date.isBefore(_month) && date.isBefore(nextMonth);
    }).toList();

    final spentMinor = expenses.fold<int>(
      0,
      (total, expense) => total + expense.amountMinor,
    );

    final limitMinor = budget?.overallLimitMinor;
    final hasBudget = limitMinor != null && limitMinor > 0;

    final remainingMinor = hasBudget ? limitMinor - spentMinor : 0;
    final progress = hasBudget ? spentMinor / limitMinor : 0.0;

    final nearLimit = hasBudget && spentMinor * 100 >= limitMinor * 80;
    String? warning;

    if (hasBudget) {
      if (spentMinor > limitMinor) {
        warning = 'Over budget by ${_money(spentMinor - limitMinor)}.';
      } else if (spentMinor == limitMinor) {
        warning = 'You have used your entire monthly budget.';
      } else if (nearLimit) {
        warning = 'You have used at least 80% of your monthly budget.';
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 164),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: _saving || (_month.year == 2000 && _month.month == 1)
                  ? null
                  : () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _monthLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: _saving || (_month.year == 9999 && _month.month == 12)
                  ? null
                  : () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: _saving ? null : _goToCurrentMonth,
            icon: const Icon(Icons.today_outlined),
            label: const Text('Current month'),
          ),
        ),
        const SizedBox(height: 8),
        FlowLiquidCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Monthly budget', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(hasBudget ? _money(limitMinor) : 'Set your budget', style: const TextStyle(color: Colors.white, fontSize: 33, fontWeight: FontWeight.w800)),
          if (hasBudget) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0).toDouble(), minHeight: 10, color: Colors.white, backgroundColor: Colors.white24),
            const SizedBox(height: 12),
            Text('${_money(remainingMinor.abs())} ${remainingMinor < 0 ? 'over budget' : 'left'} • ${(progress * 100).toStringAsFixed(0)}% used', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6), Text('${_money(spentMinor)} spent • ${expenses.length} expenses', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
          if (warning != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(warning, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ])),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : () => _editBudget(budget),
          icon: Icon(hasBudget ? Icons.edit_outlined : Icons.add),
          label: Text(
            _saving
                ? 'Saving...'
                : hasBudget
                ? 'Edit monthly budget'
                : 'Set monthly budget',
          ),
        ),
        if (!hasBudget) ...[
          const SizedBox(height: 12),
          const Text(
            'Set a budget to see your remaining amount and spending warnings.',
          ),
        ],
        const SizedBox(height: 28),
        Text('Category budgets', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Tap a category to set or edit its limit.'),
        const SizedBox(height: 16),
        if (budget == null)
          const Text(
            'Set your overall monthly budget first, then add category limits.',
          )
        else
          _buildCategoryBudgets(budget, expenses),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Budgets')),
        bottomNavigationBar: widget.onNavigate == null ? null : FlowBottomNav(selectedIndex: 2, onSelected: _saving ? null : widget.onNavigate),
        floatingActionButtonLocation: const FlowFabLocation(),
        floatingActionButton: widget.onOpenAdvisor == null ? null : FinnyButton(onPressed: widget.onOpenAdvisor),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: StreamBuilder<MonthlyBudget?>(
                key: ValueKey(MonthlyBudget.monthKey(_month)),
                stream: _budgetStream,
                builder: (context, budgetSnapshot) {
                  if (budgetSnapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Could not load your budget. '
                        'Check your connection and Firestore rules.',
                      ),
                    );
                  }

                  if (budgetSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }

                  return StreamBuilder<List<Expense>>(
                    stream: _expensesStream,
                    builder: (context, expenseSnapshot) {
                      if (expenseSnapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Could not load your expenses.'),
                        );
                      }

                      if (!expenseSnapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      return _buildContent(
                        budgetSnapshot.data,
                        expenseSnapshot.data!,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetAmountDialog extends StatefulWidget {
  final int? initialAmountMinor;
  final String title;

  const _BudgetAmountDialog({
    this.initialAmountMinor,
    this.title = 'Monthly budget',
  });

  @override
  State<_BudgetAmountDialog> createState() => _BudgetAmountDialogState();
}

class _BudgetAmountDialogState extends State<_BudgetAmountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    final amount = widget.initialAmountMinor;

    _controller = TextEditingController(
      text: amount == null
          ? ''
          : '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}',
    );
  }

  int? _parseAmount(String input) {
    final value = input.trim();

    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
      return null;
    }

    final parts = value.split('.');
    final rupees = int.parse(parts[0]);
    final cents = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;

    return rupees * 100 + cents;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(context, _parseAmount(_controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Budget amount',
            prefixText: 'Rs. ',
            hintText: '50000.00',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final amount = _parseAmount(value ?? '');

            if (amount == null ||
                amount <= 0 ||
                amount > BudgetService.maxAmountMinor) {
              return 'Enter a positive amount with up to 2 decimals.';
            }

            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
