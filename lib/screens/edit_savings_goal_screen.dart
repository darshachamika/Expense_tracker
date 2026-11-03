import 'package:flutter/material.dart';

import '../models/savings_goal.dart';
import '../services/savings_service.dart';

class EditSavingsGoalScreen extends StatefulWidget {
  final String userId;
  final SavingsGoal? goal;

  const EditSavingsGoalScreen({super.key, required this.userId, this.goal});

  @override
  State<EditSavingsGoalScreen> createState() => _EditSavingsGoalScreenState();
}

class _EditSavingsGoalScreenState extends State<EditSavingsGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;

  DateTime? _targetDate;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.goal != null;

  @override
  void initState() {
    super.initState();

    final goal = widget.goal;
    final amount = goal?.targetMinor;

    _titleController = TextEditingController(text: goal?.title ?? '');
    _amountController = TextEditingController(
      text: amount == null
          ? ''
          : '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}',
    );

    final date = goal?.targetDate?.toLocal();
    _targetDate = date == null ? null : DateUtils.dateOnly(date);
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
      initialDate: _targetDate ?? DateUtils.dateOnly(DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(9999, 12, 31),
    );

    if (selected != null && mounted) {
      setState(() => _targetDate = selected);
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = widget.goal;

      final goal = SavingsGoal(
        id: existing?.id ?? '',
        title: _titleController.text.trim(),
        targetMinor: _parseAmount(_amountController.text)!,
        targetDate: _targetDate,
        archived: existing?.archived ?? false,
      );

      final service = SavingsService(userId: widget.userId);

      if (_editing) {
        await service.updateGoal(goal);
      } else {
        await service.createGoal(goal);
      }

      if (!mounted) return;

      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Savings goal save failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Could not save the goal. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Edit Savings Goal' : 'New Savings Goal'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
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
                        labelText: 'Goal name',
                        hintText: 'e.g. Emergency fund',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a goal name.';
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
                        labelText: 'Target amount',
                        prefixText: 'Rs. ',
                        hintText: '100000.00',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final amount = _parseAmount(value ?? '');

                        if (amount == null ||
                            amount <= 0 ||
                            amount > SavingsService.maxAmountMinor) {
                          return 'Enter a positive amount with up to 2 decimals.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Target date (optional)'),
                      subtitle: Text(
                        _targetDate == null
                            ? 'No deadline'
                            : _dateLabel(_targetDate!),
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: _saving ? null : _pickDate,
                    ),
                    if (_targetDate != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _targetDate = null),
                          child: const Text('Remove target date'),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving
                            ? 'Saving...'
                            : _editing
                            ? 'Save changes'
                            : 'Create goal',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
