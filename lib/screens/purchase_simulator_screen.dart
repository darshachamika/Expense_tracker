import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/monthly_budget.dart';
import '../models/planned_bill.dart';
import '../models/purchase_simulation.dart';
import '../services/bill_service.dart';
import '../services/budget_service.dart';
import '../services/category_service.dart';
import '../services/expense_service.dart';
import 'add_expense_screen.dart';

class PurchaseSimulatorScreen extends StatefulWidget {
  final String userId;

  const PurchaseSimulatorScreen({super.key, required this.userId});

  @override
  State<PurchaseSimulatorScreen> createState() =>
      _PurchaseSimulatorScreenState();
}

class _PurchaseSimulatorScreenState extends State<PurchaseSimulatorScreen> {
  final _amountController = TextEditingController();

  late final DateTime _purchaseDate;
  late final Stream<List<Expense>> _expensesStream;
  late final Stream<List<PlannedBill>> _billsStream;
  late final Stream<List<ExpenseCategory>> _categoriesStream;
  late final Stream<MonthlyBudget?> _budgetStream;

  int? _amountMinor;
  String? _categoryId;
  bool _openingExpense = false;

  @override
  void initState() {
    super.initState();

    _purchaseDate = DateUtils.dateOnly(DateTime.now());

    _expensesStream = ExpenseService(userId: widget.userId).watchExpenses();

    _billsStream = BillService(userId: widget.userId).watchBills();

    _categoriesStream = CategoryService(userId: widget.userId)
        .watchCategories();

    _budgetStream = BudgetService(userId: widget.userId)
        .watchBudget(_purchaseDate);
  }

  int? _parseAmount(String input) {
    final value = input.trim();

    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
      return null;
    }

    final parts = value.split('.');
    final rupees = int.parse(parts[0]);
    final cents = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;

    final amount = rupees * 100 + cents;

    return amount > 0 && amount <= 99999999999 ? amount : null;
  }

  String _money(int minor) {
    final absolute = minor.abs();
    final sign = minor < 0 ? '-' : '';

    return '${sign}Rs. ${absolute ~/ 100}.'
        '${(absolute % 100).toString().padLeft(2, '0')}';
  }

  Widget _row(String label, int? amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              amount == null ? 'Not set' : _money(amount),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: amount != null && amount < 0
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recordPurchase(int amount, String categoryId) async {
    if (_openingExpense) return;

    setState(() => _openingExpense = true);

    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AddExpenseScreen(
            userId: widget.userId,
            initialAmountMinor: amount,
            initialCategoryId: categoryId,
          ),
        ),
      );

      if (!mounted) return;

      if (saved == true) {
        _amountController.clear();

        setState(() => _amountMinor = null);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase recorded as an expense.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingExpense = false);
      }
    }
  }

  Widget _withData<T>({
    required Stream<T> stream,
    required String label,
    required Widget Function(T data) builder,
  }) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load $label. '
                'Check your connection and reopen this screen.',
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // A nullable budget can legitimately have no document.
        return builder(snapshot.data as T);
      },
    );
  }

  Widget _content({
    required List<Expense> expenses,
    required List<PlannedBill> bills,
    required List<ExpenseCategory> categories,
    required MonthlyBudget? budget,
  }) {
    final activeCategories = categories
        .where((category) => !category.archived)
        .toList();

    final selectedId =
        activeCategories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;

    final amount = _amountMinor;

    final simulation = amount != null && selectedId != null
        ? PurchaseSimulation.calculate(
            purchaseAmountMinor: amount,
            categoryId: selectedId,
            purchaseDate: _purchaseDate,
            expenses: expenses,
            bills: bills,
            budget: budget,
          )
        : null;

    final remainingAfterBills = simulation?.remainingAfterBillsMinor;
    final categoryRemaining = simulation?.categoryRemainingAfterMinor;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'What if I buy this?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Estimate the impact of a purchase today using your '
          'recorded expenses, monthly budget and pending bills.',
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _amountController,
          enabled: !_openingExpense,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Purchase amount',
            prefixText: 'Rs. ',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            return _parseAmount(value ?? '') == null
                ? 'Enter a positive amount with up to 2 decimals.'
                : null;
          },
          onChanged: (value) {
            setState(() => _amountMinor = _parseAmount(value));
          },
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey(selectedId),
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in activeCategories)
              DropdownMenuItem(value: category.id, child: Text(category.name)),
          ],
          onChanged: _openingExpense
              ? null
              : (value) => setState(() => _categoryId = value),
        ),
        if (activeCategories.isEmpty) ...[
          const SizedBox(height: 12),
          const Text('Create or restore a category from Manage Categories.'),
        ],
        const SizedBox(height: 24),
        if (simulation == null)
          const Text('Enter an amount and choose a category to simulate.')
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Purchase impact',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _row(
                    'Recorded spending this month',
                    simulation.monthlySpentMinor,
                  ),
                  _row('Proposed purchase', simulation.purchaseAmountMinor),
                  _row(
                    'Spending after purchase',
                    simulation.monthlySpentAfterMinor,
                  ),
                  const Divider(),
                  _row(
                    'Monthly budget remaining before',
                    simulation.monthlyRemainingBeforeMinor,
                  ),
                  _row(
                    'Monthly budget remaining after',
                    simulation.monthlyRemainingAfterMinor,
                  ),
                  _row(
                    'Category limit remaining after',
                    simulation.categoryRemainingAfterMinor,
                  ),
                  const Divider(),
                  _row(
                    'Recorded unpaid bills due by month-end',
                    simulation.pendingBillsMinor,
                  ),
                  _row(
                    'Budget left after purchase and bills',
                    simulation.remainingAfterBillsMinor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (budget == null)
            const Text(
              'No monthly budget is set. '
              'Set one to estimate the remaining budget.',
            ),
          if (categoryRemaining != null && categoryRemaining < 0)
            Text(
              'This purchase exceeds the category limit by '
              '${_money(categoryRemaining.abs())}.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (remainingAfterBills != null && remainingAfterBills < 0) ...[
            const SizedBox(height: 8),
            Text(
              'The monthly budget would be short by '
              '${_money(remainingAfterBills.abs())} '
              'after this purchase and recorded pending bills.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openingExpense
                ? null
                : () => _recordPurchase(
                    simulation.purchaseAmountMinor,
                    selectedId!,
                  ),
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Review and record purchase'),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'This is a budget estimate, not a bank balance or a guarantee '
          'that a purchase is affordable. Only recorded bill occurrences '
          'are included. Overdue unpaid bills are included too.',
        ),
      ],
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Simulator')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: _withData<List<Expense>>(
              stream: _expensesStream,
              label: 'expenses',
              builder: (expenses) => _withData<List<PlannedBill>>(
                stream: _billsStream,
                label: 'planned bills',
                builder: (bills) => _withData<List<ExpenseCategory>>(
                  stream: _categoriesStream,
                  label: 'categories',
                  builder: (categories) => _withData<MonthlyBudget?>(
                    stream: _budgetStream,
                    label: 'monthly budget',
                    builder: (budget) => _content(
                      expenses: expenses,
                      bills: bills,
                      categories: categories,
                      budget: budget,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
