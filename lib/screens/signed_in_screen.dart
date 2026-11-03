import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/expense_category.dart';
import '../services/auth_service.dart';
import '../services/category_service.dart';
import '../services/expense_service.dart';
import 'add_expense_screen.dart';
import 'category_manager_screen.dart';
import 'monthly_budget_screen.dart';
import 'dashboard_screen.dart';
import 'savings_goals_screen.dart';
import 'planned_bills_screen.dart';
import 'purchase_simulator_screen.dart';

class SignedInScreen extends StatefulWidget {
  final User user;

  const SignedInScreen({super.key, required this.user});

  @override
  State<SignedInScreen> createState() => _SignedInScreenState();
}

class _SignedInScreenState extends State<SignedInScreen> {
  final _authService = AuthService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String? _filterCategoryId;
  DateTimeRange? _filterDateRange;

  late final ExpenseService _expenseService;
  late final Stream<List<Expense>> _expensesStream;

  StreamSubscription<List<ExpenseCategory>>? _categorySubscription;

  Map<String, ExpenseCategory> _categoriesById = {};

  bool _categoriesLoading = true;
  bool _categoriesFailed = false;
  bool _signingOut = false;
  bool _deletingExpense = false;

  bool get _busy => _signingOut || _deletingExpense;

  bool _isBillPayment(Expense expense) => expense.id.startsWith('bill_');

  @override
  void initState() {
    super.initState();

    _expenseService = ExpenseService(userId: widget.user.uid);
    _expensesStream = _expenseService.watchExpenses();

    _categorySubscription = CategoryService(userId: widget.user.uid)
        .watchCategories()
        .listen(
          (categories) {
            if (!mounted) return;

            setState(() {
              _categoriesById = {
                for (final category in categories) category.id: category,
              };
              _categoriesLoading = false;
              _categoriesFailed = false;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Category names failed to load: $error');

            if (!mounted) return;

            setState(() {
              _categoriesLoading = false;
              _categoriesFailed = true;
            });
          },
        );
  }

  void _filterToday() {
    final today = DateUtils.dateOnly(DateTime.now());

    setState(() {
      _filterDateRange = DateTimeRange(start: today, end: today);
    });
  }

  void _filterThisMonth() {
    final now = DateTime.now();

    setState(() {
      _filterDateRange = DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      );
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();

    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month + 1, 0),
      initialDateRange: _filterDateRange,
      helpText: 'Select expense dates',
    );

    if (!mounted || selected == null) return;

    setState(() => _filterDateRange = selected);
  }

  List<Expense> _filterExpenses(List<Expense> expenses) {
    final query = _searchQuery.trim().toLowerCase();
    final range = _filterDateRange;

    return expenses.where((expense) {
      final matchesCategory =
          _filterCategoryId == null || expense.categoryId == _filterCategoryId;

      final matchesSearch =
          query.isEmpty ||
          expense.title.toLowerCase().contains(query) ||
          expense.note.toLowerCase().contains(query);

      bool matchesDate = true;

      if (range != null) {
        final date = DateUtils.dateOnly(expense.expenseDate.toLocal());
        final start = DateUtils.dateOnly(range.start);
        final end = DateUtils.dateOnly(range.end);

        matchesDate = !date.isBefore(start) && !date.isAfter(end);
      }

      return matchesCategory && matchesSearch && matchesDate;
    }).toList();
  }

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _filterCategoryId = null;
      _filterDateRange = null;
    });
  }

  String _categoryLabel(String id) {
    final category = _categoriesById[id];

    if (category != null) {
      return category.archived ? '${category.name} (Archived)' : category.name;
    }

    if (_categoriesLoading) return 'Loading category…';
    if (_categoriesFailed) return 'Category unavailable';

    return 'Unknown category';
  }

  String _formatMoney(int amountMinor) {
    final rupees = amountMinor ~/ 100;
    final cents = (amountMinor % 100).toString().padLeft(2, '0');

    return 'Rs. $rupees.$cents';
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  Future<void> _addExpense() async {
    if (_busy) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(userId: widget.user.uid),
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expense saved successfully.')),
    );
  }

  Future<void> _editExpense(Expense expense) async {
    if (_busy || _isBillPayment(expense)) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddExpenseScreen(userId: widget.user.uid, expense: expense),
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expense updated successfully.')),
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    if (_busy || _isBillPayment(expense)) return;

    // Lock actions while confirming and deleting.
    setState(() => _deletingExpense = true);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete expense?'),
          content: Text(
            'Delete "${expense.title}" '
            '(${_formatMoney(expense.amountMinor)})?\n\n'
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null || currentUser.uid != widget.user.uid) {
        throw StateError('Your session changed. Please sign in again.');
      }

      await _expenseService.deleteExpense(expense.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted successfully.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Expense deletion failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the expense. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingExpense = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;

    setState(() => _signingOut = true);

    try {
      await _authService.signOut();
    } catch (error) {
      debugPrint('Sign-out failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not finish signing out. Try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categorySubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Expense Tracker'),
          actions: [
            IconButton(
              tooltip: 'Dashboard',
              icon: const Icon(Icons.dashboard_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DashboardScreen(userId: widget.user.uid),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Monthly budget',
              icon: const Icon(Icons.savings_outlined),
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MonthlyBudgetScreen(userId: widget.user.uid),
                        ),
                      );
                    },
            ),
            IconButton(
              tooltip: 'Manage categories',
              icon: const Icon(Icons.category_outlined),
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CategoryManagerScreen(userId: widget.user.uid),
                        ),
                      );
                    },
            ),
            IconButton(
              onPressed: _busy ? null : _signOut,
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : _addExpense,
          icon: const Icon(Icons.add),
          label: const Text('Add Expense'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: StreamBuilder<List<Expense>>(
                stream: _expensesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Could not load expenses. '
                        'Please try again later.',
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allExpenses = snapshot.data!;
                  final expenses = _filterExpenses(allExpenses);

                  final hasFilters =
                      _searchQuery.trim().isNotEmpty ||
                      _filterCategoryId != null ||
                      _filterDateRange != null;

                  final totalMinor = expenses.fold<int>(
                    0,
                    (total, expense) => total + expense.amountMinor,
                  );

                  final categoryOptions = _categoriesById.values.toList()
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );

                  final selectedCategoryExists =
                      _filterCategoryId == null ||
                      _categoriesById.containsKey(_filterCategoryId);

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PurchaseSimulatorScreen(
                                userId: widget.user.uid,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('Purchase simulator'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PlannedBillsScreen(userId: widget.user.uid),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Planned bills'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  SavingsGoalsScreen(userId: widget.user.uid),
                            ),
                          );
                        },
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Savings goals'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Hello, ${widget.user.displayName ?? 'there'}',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'Search expenses',
                          hintText: 'Search title or note',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_filterCategoryId),
                        initialValue: _filterCategoryId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Filter by category',
                          border: const OutlineInputBorder(),
                          helperText: _categoriesLoading
                              ? 'Loading categories…'
                              : _categoriesFailed
                              ? 'Could not load categories.'
                              : null,
                        ),
                        hint: const Text('All categories'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All categories'),
                          ),
                          ...categoryOptions.map(
                            (category) => DropdownMenuItem<String>(
                              value: category.id,
                              child: Text(
                                category.archived
                                    ? '${category.name} (Archived)'
                                    : category.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (!selectedCategoryExists)
                            DropdownMenuItem<String>(
                              value: _filterCategoryId,
                              child: const Text('Unavailable category'),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _filterCategoryId = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _filterToday,
                            child: const Text('Today'),
                          ),
                          OutlinedButton(
                            onPressed: _filterThisMonth,
                            child: const Text('This month'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickDateRange,
                            icon: const Icon(Icons.date_range_outlined),
                            label: const Text('Choose dates'),
                          ),
                          if (_filterDateRange != null)
                            TextButton(
                              onPressed: () {
                                setState(() => _filterDateRange = null);
                              },
                              child: const Text('All dates'),
                            ),
                        ],
                      ),
                      if (_filterDateRange != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_formatDate(_filterDateRange!.start)}'
                          ' → '
                          '${_formatDate(_filterDateRange!.end)}',
                        ),
                      ],
                      if (hasFilters)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear filters'),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasFilters
                                    ? 'Filtered spending'
                                    : 'Total recorded spending',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatMoney(totalMinor),
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                hasFilters
                                    ? '${expenses.length} of '
                                          '${allExpenses.length} expenses'
                                    : '${expenses.length} expenses',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Your expenses', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      if (expenses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            allExpenses.isEmpty
                                ? 'No expenses yet. Tap Add Expense to begin.'
                                : 'No expenses match your filters.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ...expenses.map(
                          (expense) => Card(
                            child: ListTile(
                              onTap: _busy || _isBillPayment(expense)
                                  ? null
                                  : () => _editExpense(expense),
                              leading: const CircleAvatar(
                                child: Icon(Icons.receipt_long_outlined),
                              ),
                              title: Text(
                                expense.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_categoryLabel(expense.categoryId)} · '
                                '${_formatDate(expense.expenseDate.toLocal())}'
                                '${_isBillPayment(expense) ? '\nBill payment • Read-only' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatMoney(expense.amountMinor),
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  if (_isBillPayment(expense))
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Tooltip(
                                        message:
                                            'This expense was created from a bill payment. '
                                            'It cannot be edited or deleted separately.',
                                        child: Icon(Icons.lock_outline),
                                      ),
                                    )
                                  else
                                    PopupMenuButton<String>(
                                      tooltip: 'Expense actions',
                                      enabled: !_busy,
                                      onSelected: (action) async {
                                        if (action == 'edit') {
                                          await _editExpense(expense);
                                        } else if (action == 'delete') {
                                          await _deleteExpense(expense);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined),
                                              SizedBox(width: 12),
                                              Text('Edit'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline),
                                              SizedBox(width: 12),
                                              Text('Delete'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
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
