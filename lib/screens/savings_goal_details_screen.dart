import 'package:flutter/material.dart';

import '../models/savings_contribution.dart';
import '../models/savings_goal.dart';
import '../services/savings_service.dart';
import '../widgets/flow_goal_savings_plan.dart';

String _money(int minor) {
  return 'Rs. ${minor ~/ 100}.'
      '${(minor % 100).toString().padLeft(2, '0')}';
}

String _dateLabel(DateTime date) {
  final local = date.toLocal();

  return '${local.year}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class SavingsGoalDetailsScreen extends StatefulWidget {
  final String userId;
  final String goalId;

  const SavingsGoalDetailsScreen({
    super.key,
    required this.userId,
    required this.goalId,
  });

  @override
  State<SavingsGoalDetailsScreen> createState() =>
      _SavingsGoalDetailsScreenState();
}

class _SavingsGoalDetailsScreenState extends State<SavingsGoalDetailsScreen> {
  late final SavingsService _service;
  late final Stream<SavingsGoal?> _goalStream;
  late final Stream<List<SavingsContribution>> _contributionsStream;

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _service = SavingsService(userId: widget.userId);
    _goalStream = _service.watchGoal(widget.goalId);
    _contributionsStream = _service.watchContributions(widget.goalId);
  }

  Future<void> _run(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await action();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error, stackTrace) {
      debugPrint('Savings contribution action failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update savings. '
            'Check your connection and whether the goal is active.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _addContribution() async {
    if (_busy) return;

    final contribution = await showDialog<SavingsContribution>(
      context: context,
      builder: (_) => const _ContributionDialog(),
    );

    if (contribution == null || !mounted) return;

    await _run(() async {
      await _service.addContribution(
        goalId: widget.goalId,
        amountMinor: contribution.amountMinor,
        contributionDate: contribution.contributionDate,
        note: contribution.note,
      );
    }, 'Contribution added.');
  }

  Future<void> _removeContribution(SavingsContribution contribution) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove contribution?'),
        content: Text(
          'Remove the ${_money(contribution.amountMinor)} record? '
          'This reduces the tracked savings total. '
          'It does not move money from a bank account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _run(
      () => _service.removeContribution(
        goalId: widget.goalId,
        contributionId: contribution.id,
      ),
      'Contribution removed.',
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
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

  Widget _content(SavingsGoal goal, List<SavingsContribution> contributions) {
    final savedMinor = contributions.fold<int>(
      0,
      (total, contribution) => total + contribution.amountMinor,
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(goal.title, style: Theme.of(context).textTheme.headlineSmall),
        if (goal.archived) ...[
          const SizedBox(height: 8),
          const Text('Archived • restore this goal to add contributions.'),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row('Target', _money(goal.targetMinor)),
                _row('Saved', _money(savedMinor)),
                _row('Remaining', _money(goal.remainingMinor(savedMinor))),
                _row(
                  'Target date',
                  goal.targetDate == null
                      ? 'No deadline'
                      : _dateLabel(goal.targetDate!),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: goal.progress(savedMinor),
                  minHeight: 10,
                ),
                const SizedBox(height: 8),
                Text(
                  goal.archived && goal.isCompleted(savedMinor)
                      ? 'Goal completed!'
                      : '${(goal.progress(savedMinor) * 100).toStringAsFixed(1)}% saved',
                ),
                if (!goal.archived) ...[
                  const SizedBox(height: 16),
                  FlowGoalSavingsPlan(goal: goal, savedMinor: savedMinor),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy || goal.archived ? null : _addContribution,
          icon: const Icon(Icons.add),
          label: Text(_busy ? 'Updating...' : 'Add contribution'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Contributions track money you have set aside. '
          'They do not transfer money or add expenses.',
        ),
        const SizedBox(height: 28),
        Text(
          'Contribution history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (contributions.isEmpty)
          const Text('No contributions yet.')
        else
          for (final contribution in contributions)
            Card(
              child: ListTile(
                title: Text(_money(contribution.amountMinor)),
                subtitle: Text(
                  '${_dateLabel(contribution.contributionDate)}'
                  '${contribution.note.isEmpty ? '' : '\n${contribution.note}'}',
                ),
                trailing: IconButton(
                  tooltip: 'Remove contribution record',
                  onPressed: _busy
                      ? null
                      : () => _removeContribution(contribution),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Savings Goal')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: StreamBuilder<SavingsGoal?>(
                stream: _goalStream,
                builder: (context, goalSnapshot) {
                  if (goalSnapshot.hasError) {
                    return const Text('Could not load this goal.');
                  }

                  if (goalSnapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }

                  final goal = goalSnapshot.data;

                  if (goal == null) {
                    return const Text('This goal is unavailable.');
                  }

                  return StreamBuilder<List<SavingsContribution>>(
                    stream: _contributionsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Could not load contribution history. '
                            'Reopen this screen to retry.',
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      return _content(goal, snapshot.data!);
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

class _ContributionDialog extends StatefulWidget {
  const _ContributionDialog();

  @override
  State<_ContributionDialog> createState() => _ContributionDialogState();
}

class _ContributionDialogState extends State<_ContributionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _date = DateUtils.dateOnly(DateTime.now());

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

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );

    if (selected != null && mounted) {
      setState(() => _date = selected);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      SavingsContribution(
        id: '',
        amountMinor: _parseAmount(_amountController.text)!,
        contributionDate: _date,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add contribution'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'Rs. ',
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
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(_dateLabel(_date)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
