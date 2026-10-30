import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../services/expense_service.dart';


class AddExpenseScreen extends StatefulWidget {
  final String userId;

  const AddExpenseScreen({super.key, required this.userId});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  // Starter choices. User-managed categories come in a later branch.
  static const _categories = {
    'food': 'Food & Drinks',
    'transport': 'Transport',
    'home': 'Home & Utilities',
    'shopping': 'Shopping',
    'health': 'Health & Wellness',
    'entertainment': 'Entertainment',
    'education': 'Education',
    'other': 'Other',
  };

  String _categoryId = 'food';
  String _paymentMethod = 'cash';
  DateTime _expenseDate = DateUtils.dateOnly(DateTime.now());

  bool _saving = false;
  String? _error;

  // Convert rupees into integer cents without floating-point arithmetic.
  int? _parseAmountMinor(String input) {
    final value = input.trim();

    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
      return null;
    }

    final parts = value.split('.');
    final rupees = int.parse(parts[0]);
    final cents = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;

    return rupees * 100 + cents;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2000),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );

    if (selected != null && mounted) {
      setState(() => _expenseDate = selected);
    }
  }

  Future<void> _saveExpense() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null || currentUser.uid != widget.userId) {
        throw StateError('Your session changed. Please sign in again.');
      }

      final expense = Expense(
        id: '',
        title: _titleController.text.trim(),
        amountMinor: _parseAmountMinor(_amountController.text)!,
        categoryId: _categoryId,
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
        expenseDate: _expenseDate,
      );

      final service = ExpenseService(userId: currentUser.uid);
      await service.createExpense(expense);

      if (!mounted) return;

      setState(() => _saving = false);
      Navigator.pop(context, true);
    } on FirebaseException catch (error) {
      debugPrint(
        'Expense save failed: '
        '${error.plugin}/${error.code}: ${error.message}',
      );

      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Save failed (${error.code}).';
      });
    } catch (error, stackTrace) {
      debugPrint('Expense save failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Could not save the expense. See terminal details.';
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Expense')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextFormField(
                  controller: _titleController,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Lunch',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter an expense title.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'Rs. ',
                    hintText: '1200.50',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = _parseAmountMinor(value ?? '');

                    if (amount == null || amount <= 0) {
                      return 'Enter a positive amount with up to 2 decimals.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _categoryId = value);
                          }
                        },
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _paymentMethod = value);
                          }
                        },
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Expense date'),
                  subtitle: Text(_formatDate(_expenseDate)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _saving ? null : _pickDate,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _noteController,
                  enabled: !_saving,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _saveExpense,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_saving ? 'Saving...' : 'Save Expense'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
