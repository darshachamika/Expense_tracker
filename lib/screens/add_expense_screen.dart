import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/expense_category.dart';
import '../services/category_service.dart';
import '../services/expense_service.dart';

class AddExpenseScreen extends StatefulWidget {
  final String userId;
  final Expense? expense;

  const AddExpenseScreen({super.key, required this.userId, this.expense});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String? _categoryId;
  List<ExpenseCategory> _categories = [];

  StreamSubscription<List<ExpenseCategory>>? _categorySubscription;

  bool _categoriesLoading = true;
  String? _categoryError;

  String _paymentMethod = 'cash';
  DateTime _expenseDate = DateUtils.dateOnly(DateTime.now());

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.expense != null;

  bool get _isBillPayment => widget.expense?.id.startsWith('bill_') == true;

  List<ExpenseCategory> get _selectableCategories {
    final originalCategoryId = widget.expense?.categoryId;

    return _categories.where((category) {
      // Preserve an existing expense's archived category while editing.
      return !category.archived || category.id == originalCategoryId;
    }).toList();
  }

  @override
  void initState() {
    super.initState();

    final expense = widget.expense;

    if (expense != null) {
      _titleController.text = expense.title;

      final rupees = expense.amountMinor ~/ 100;
      final cents = (expense.amountMinor % 100).toString().padLeft(2, '0');

      _amountController.text = '$rupees.$cents';
      _noteController.text = expense.note;
      _categoryId = expense.categoryId;
      _paymentMethod = expense.paymentMethod;
      _expenseDate = DateUtils.dateOnly(expense.expenseDate);
    }

    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoryError = null;
    });

    try {
      await _categorySubscription?.cancel();
      _categorySubscription = null;

      if (!mounted) return;

      final service = CategoryService(userId: widget.userId);

      // Add missing starter categories without resetting existing ones.
      await service.ensureDefaultCategories();

      if (!mounted) return;

      _categorySubscription = service.watchCategories().listen(
        (categories) {
          if (!mounted) return;

          setState(() {
            _categories = categories;
            _categoriesLoading = false;
            _categoryError = null;

            final available = _selectableCategories;
            final selectionExists = available.any(
              (category) => category.id == _categoryId,
            );

            if (!selectionExists) {
              // Require an explicit choice if an old selection is unavailable.
              // A new form without a selection can use the first active item.
              if (_categoryId == null && !_isEditing) {
                _categoryId = available.isEmpty ? null : available.first.id;
              } else {
                _categoryId = null;
              }
            }
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          _handleCategoryError(error);
        },
      );
    } catch (error) {
      _handleCategoryError(error);
    }
  }

  void _handleCategoryError(Object error) {
    debugPrint('Category loading failed: $error');

    if (!mounted) return;

    setState(() {
      _categoriesLoading = false;
      _categoryError = 'Could not load categories. Please retry.';
    });
  }

  // Convert rupees to integer cents without floating-point arithmetic.
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

    if (!mounted || selected == null) return;

    setState(() => _expenseDate = selected);
  }

  Future<void> _saveExpense() async {
    if (_saving) return;

    if (_isBillPayment) {
      setState(() {
        _error = 'Bill payment expenses cannot be edited separately.';
      });
      return;
    }

    if (_categoriesLoading || _categoryError != null) {
      setState(() {
        _error = 'Load categories successfully before saving.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final selectedCategoryId = _categoryId;

    if (selectedCategoryId == null ||
        !_selectableCategories.any(
          (category) => category.id == selectedCategoryId,
        )) {
      setState(() {
        _error = 'Please select an available category.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null || currentUser.uid != widget.userId) {
        throw StateError('Your session changed. Please sign in again.');
      }

      final existing = widget.expense;

      final expense = Expense(
        id: existing?.id ?? '',
        title: _titleController.text.trim(),
        amountMinor: _parseAmountMinor(_amountController.text)!,
        categoryId: selectedCategoryId,
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
        expenseDate: _expenseDate,
        createdAt: existing?.createdAt,
      );

      final service = ExpenseService(userId: currentUser.uid);

      if (_isEditing) {
        await service.updateExpense(expense);
      } else {
        await service.createExpense(expense);
      }

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
        _error = 'Save failed (${error.code}). Please retry.';
      });
    } catch (error, stackTrace) {
      debugPrint('Expense save failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Could not save the expense. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _categorySubscription?.cancel();
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectableCategories = _selectableCategories;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isBillPayment
                ? 'Bill Payment'
                : _isEditing
                ? 'Edit Expense'
                : 'Add Expense',
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_isBillPayment) ...[
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This expense was created from a bill payment. '
                              'It cannot be edited or deleted separately.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _titleController,
                  enabled: !_saving && !_isBillPayment,
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
                  enabled: !_saving && !_isBillPayment,
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
                if (_categoriesLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(),
                  )
                else if (_categoryError != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _categoryError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _saving ? null : _loadCategories,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(_categoryId),
                    initialValue: _categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select a category'),
                    items: selectableCategories.map((category) {
                      return DropdownMenuItem<String>(
                        value: category.id,
                        child: Text(
                          category.archived
                              ? '${category.name} (Archived)'
                              : category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: _saving || _isBillPayment
                        ? null
                        : (value) {
                            setState(() => _categoryId = value);
                          },
                    validator: (value) {
                      if (value == null) {
                        return 'Select a category. Create or restore one if needed.';
                      }

                      return null;
                    },
                  ),
                  if (selectableCategories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No categories available. Go back to Manage Categories '
                        'and create or restore a category.',
                      ),
                    ),
                ],
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
                  onChanged: _saving || _isBillPayment
                      ? null
                      : (value) {
                          if (value == null) return;

                          setState(() => _paymentMethod = value);
                        },
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Expense date'),
                  subtitle: Text(_formatDate(_expenseDate)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _saving || _isBillPayment ? null : _pickDate,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _noteController,
                  enabled: !_saving && !_isBillPayment,
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
                  onPressed:
                      _saving ||
                          _isBillPayment ||
                          _categoriesLoading ||
                          _categoryError != null ||
                          selectableCategories.isEmpty
                      ? null
                      : _saveExpense,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _saving
                          ? 'Saving...'
                          : _isEditing
                          ? 'Save Changes'
                          : 'Save Expense',
                    ),
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
