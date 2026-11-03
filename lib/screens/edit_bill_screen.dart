import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../models/planned_bill.dart';
import '../services/bill_service.dart';
import '../services/category_service.dart';

class EditBillScreen extends StatefulWidget {
  final String userId;
  final PlannedBill? bill;

  const EditBillScreen({super.key, required this.userId, this.bill});

  @override
  State<EditBillScreen> createState() => _EditBillScreenState();
}

class _EditBillScreenState extends State<EditBillScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final Stream<List<ExpenseCategory>> _categoriesStream;

  String? _categoryId;
  String _paymentMethod = 'cash';
  BillRecurrence _recurrence = BillRecurrence.none;
  DateTime _dueDate = DateUtils.dateOnly(DateTime.now());

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final bill = widget.bill;
    final amount = bill?.amountMinor;

    _titleController = TextEditingController(text: bill?.title ?? '');
    _amountController = TextEditingController(
      text: amount == null
          ? ''
          : '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}',
    );
    _noteController = TextEditingController(text: bill?.note ?? '');

    _categoriesStream = CategoryService(userId: widget.userId)
        .watchCategories();

    if (bill != null) {
      _categoryId = bill.categoryId;
      _paymentMethod = bill.paymentMethod;
      _recurrence = bill.recurrence;
      _dueDate = DateUtils.dateOnly(bill.dueDate.toLocal());
    }
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

  String _dateLabel(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(9999, 12, 31),
    );

    if (selected != null && mounted) {
      setState(() => _dueDate = selected);
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final categoryId = _categoryId;
    if (categoryId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = widget.bill;

      final preserveBillingDay =
          existing != null &&
          existing.recurrence == BillRecurrence.monthly &&
          _recurrence == BillRecurrence.monthly &&
          DateUtils.isSameDay(existing.dueDate.toLocal(), _dueDate);

      final bill = PlannedBill(
        id: existing?.id ?? '',
        seriesId: existing?.seriesId ?? '',
        title: _titleController.text.trim(),
        amountMinor: _parseAmount(_amountController.text)!,
        categoryId: categoryId,
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
        dueDate: _dueDate,
        recurrence: _recurrence,
        recurrenceDay: preserveBillingDay
            ? existing.recurrenceDay
            : _dueDate.day,
      );

      final service = BillService(userId: widget.userId);

      if (existing == null) {
        await service.createBill(bill);
      } else {
        await service.updateBill(bill);
      }

      if (!mounted) return;

      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Bill save failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _saving = false;
        _error =
            'Could not save the bill. '
            'Check your connection and whether it is already paid.';
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

  Widget _form(List<ExpenseCategory> categories) {
    final options = categories
        .where(
          (category) =>
              !category.archived || category.id == widget.bill?.categoryId,
        )
        .toList();

    final originalCategoryId = widget.bill?.categoryId;

    if (originalCategoryId != null &&
        !options.any((category) => category.id == originalCategoryId)) {
      options.add(
        ExpenseCategory(
          id: originalCategoryId,
          name: 'Unavailable category',
          archived: true,
        ),
      );
    }

    final selectedId = options.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            controller: _titleController,
            enabled: !_saving,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Bill name',
              hintText: 'e.g. Electricity',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter a bill name.';
              }

              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: 'Rs. ',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final amount = _parseAmount(value ?? '');

              if (amount == null ||
                  amount <= 0 ||
                  amount > BillService.maxAmountMinor) {
                return 'Enter a positive amount with up to 2 decimals.';
              }

              return null;
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
              for (final category in options)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(
                    category.archived
                        ? '${category.name} (Archived)'
                        : category.name,
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _categoryId = value),
            validator: (value) => value == null ? 'Choose a category.' : null,
          ),
          if (options.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('Create a category from the home screen first.'),
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
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _paymentMethod = value);
                    }
                  },
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<BillRecurrence>(
            initialValue: _recurrence,
            decoration: const InputDecoration(
              labelText: 'Repeat',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: BillRecurrence.none,
                child: Text('One time'),
              ),
              DropdownMenuItem(
                value: BillRecurrence.monthly,
                child: Text('Monthly'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _recurrence = value);
                    }
                  },
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Due date'),
            subtitle: Text(_dateLabel(_dueDate)),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save bill'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.bill == null ? 'New Bill' : 'Edit Bill'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: StreamBuilder<List<ExpenseCategory>>(
                stream: _categoriesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Could not load categories. Reopen this screen to retry.',
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  return _form(snapshot.data!);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
