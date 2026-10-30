import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../services/auth_service.dart';
import '../services/expense_service.dart';
import 'add_expense_screen.dart';

class SignedInScreen extends StatefulWidget {
  final User user;

  const SignedInScreen({super.key, required this.user});

  @override
  State<SignedInScreen> createState() => _SignedInScreenState();
}

class _SignedInScreenState extends State<SignedInScreen> {
  final _authService = AuthService();

  late final ExpenseService _expenseService;
  late final Stream<List<Expense>> _expensesStream;

  bool _signingOut = false;

  @override
  void initState() {
    super.initState();

    _expenseService = ExpenseService(userId: widget.user.uid);
    _expensesStream = _expenseService.watchExpenses();
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
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
                      'Check the terminal for details.',
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final expenses = snapshot.data!;

                final totalMinor = expenses.fold<int>(
                  0,
                  (total, expense) => total + expense.amountMinor,
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  children: [
                    Text(
                      'Hello, ${widget.user.displayName ?? 'there'}',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total recorded spending'),
                            const SizedBox(height: 8),
                            Text(
                              _formatMoney(totalMinor),
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text('${expenses.length} expenses'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Your expenses', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    if (expenses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'No expenses yet. Tap Add Expense to begin.',
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
                              '${expense.categoryId} · '
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
