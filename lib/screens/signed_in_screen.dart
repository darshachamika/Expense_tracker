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

  late final ExpenseService _expenseService;
  late final Stream<List<Expense>> _expensesStream;

  StreamSubscription<List<ExpenseCategory>>? _categorySubscription;

  Map<String, ExpenseCategory> _categoriesById = {};

  bool _categoriesLoading = true;
  bool _categoriesFailed = false;
  bool _signingOut = false;

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

  List<Expense> _filterExpenses(List<Expense> expenses) {
    final query = _searchQuery.trim().toLowerCase();

    return expenses.where((expense) {
      final matchesCategory =
          _filterCategoryId == null || expense.categoryId == _filterCategoryId;

      final matchesSearch =
          query.isEmpty ||
          expense.title.toLowerCase().contains(query) ||
          expense.note.toLowerCase().contains(query);

      return matchesCategory && matchesSearch;
    }).toList();
  }

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _filterCategoryId = null;
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

  Future<void> _signOut() async {
    if (_signingOut) return;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          IconButton(
            tooltip: 'Manage categories',
            icon: const Icon(Icons.category_outlined),
            onPressed: _signingOut
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
            onPressed: _signingOut ? null : _signOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _signingOut ? null : _addExpense,
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
                    _searchQuery.trim().isNotEmpty || _filterCategoryId != null;

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
                              '${_formatDate(expense.expenseDate)}',
                            ),
                            trailing: Text(
                              _formatMoney(expense.amountMinor),
                              style: theme.textTheme.titleSmall,
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
    );
  }
}
