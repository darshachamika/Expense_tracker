import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/monthly_budget.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final String userId;

  const MonthlyBudgetScreen({super.key, required this.userId});

  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  late DateTime _month;
  late final BudgetService _budgetService;
  late Stream<MonthlyBudget?> _budgetStream;
  late final Stream<List<Expense>> _expensesStream;

  bool _saving = false;

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

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
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

    final reachedLimit = hasBudget && spentMinor >= limitMinor;
    final nearLimit = hasBudget && spentMinor * 100 >= limitMinor * 80;

    final colors = Theme.of(context).colorScheme;
    final progressColor = reachedLimit
        ? colors.error
        : nearLimit
        ? Colors.orange
        : colors.primary;

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
      padding: const EdgeInsets.all(24),
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
        const Text('Track spending against the selected month’s budget.'),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _summaryRow(
                  'Budget',
                  hasBudget ? _money(limitMinor) : 'Not set',
                ),
                _summaryRow('Spent', _money(spentMinor)),
                if (hasBudget)
                  _summaryRow(
                    remainingMinor < 0 ? 'Over budget' : 'Remaining',
                    _money(remainingMinor.abs()),
                  ),
                _summaryRow('Expenses', '${expenses.length}'),
                if (hasBudget) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0).toDouble(),
                    minHeight: 10,
                    color: progressColor,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(1)}% used'),
                ],
                if (warning != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    warning,
                    style: TextStyle(
                      color: progressColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Monthly Budget')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
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

  const _BudgetAmountDialog({this.initialAmountMinor});

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
      title: const Text('Monthly budget'),
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
