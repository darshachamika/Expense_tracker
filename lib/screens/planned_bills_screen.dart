import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/planned_bill.dart';
import '../services/bill_service.dart';
import 'edit_bill_screen.dart';

enum _BillAction { undoPayment, archive, restore, delete }

class PlannedBillsScreen extends StatefulWidget {
  final String userId;

  const PlannedBillsScreen({super.key, required this.userId});

  @override
  State<PlannedBillsScreen> createState() => _PlannedBillsScreenState();
}

class _PlannedBillsScreenState extends State<PlannedBillsScreen> {
  late final BillService _service;
  late final Stream<List<PlannedBill>> _billsStream;

  bool _showPaid = false;
  bool _showArchived = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _service = BillService(userId: widget.userId);
    _billsStream = _service.watchBills();
  }

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

  Future<void> _openEditor([PlannedBill? bill]) async {
    if (_busy || bill?.isPaid == true) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditBillScreen(userId: widget.userId, bill: bill),
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bill saved.')));
    }
  }

  Future<void> _markAsPaid(PlannedBill bill) async {
    if (_busy || bill.isPaid) return;

    setState(() => _busy = true);

    try {
      final today = DateUtils.dateOnly(DateTime.now());

      final paymentDate = await showDatePicker(
        context: context,
        initialDate: today,
        firstDate: DateTime(2000),
        lastDate: today,
        helpText: 'When did you pay this bill?',
      );

      if (paymentDate == null || !mounted) return;

      final nextDate = bill.nextDueDate;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Record bill payment?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.title,
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text('Amount: ${_money(bill.amountMinor)}'),
                Text('Payment date: ${_dateLabel(paymentDate)}'),
                const SizedBox(height: 12),
                const Text(
                  'This marks the bill as paid and records an expense. '
                  'It does not transfer money.',
                ),
                if (nextDate != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'The next monthly bill will be due on '
                    '${_dateLabel(nextDate)}.',
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Use Undo payment from this bill to reverse the recorded payment.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Record payment'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      await _service.markAsPaid(billId: bill.id, paymentDate: paymentDate);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment recorded. The linked expense is available.'),
        ),
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Bill payment failed: ${error.code}: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record payment (${error.code}).')),
      );
    } catch (error, stackTrace) {
      debugPrint('Bill payment failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not record payment. '
            'Reopen this screen and check the bill status before retrying.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changeBill(PlannedBill bill, _BillAction action) async {
    if (_busy) return;
    final monthly = bill.recurrence == BillRecurrence.monthly;
    final undoRecurrence = monthly
        ? '\n\nThe untouched next monthly bill will also be removed. '
              'If it has been edited or paid, Undo will stop.'
        : '';
    final deleteRecurrence = monthly
        ? ' Its monthly reminders will stop because the next occurrence '
              'is created when this bill is paid.'
        : '';
    final (title, explanation, button, success) = switch (action) {
      _BillAction.undoPayment => (
        'Undo this payment?',
        'Remove the linked ${_money(bill.amountMinor)} expense and return '
            'this bill to Pending. Spending for its payment month will decrease.'
            '$undoRecurrence',
        'Undo payment',
        'Payment reversed. The bill is pending and its expense was removed.',
      ),
      _BillAction.archive => (
        'Archive this paid bill?',
        'Move this paid occurrence to Archived. Its payment history and '
            'recorded spending will stay available.',
        'Archive',
        'Paid bill archived.',
      ),
      _BillAction.restore => (
        'Restore this bill?',
        'Return this paid occurrence to the paid bills list.',
        'Restore',
        'Paid bill restored.',
      ),
      _BillAction.delete => (
        'Delete this pending bill?',
        'Delete this unpaid occurrence.$deleteRecurrence',
        'Delete bill',
        'Pending bill deleted.',
      ),
    };
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text('${bill.title}\n\n$explanation'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(button),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final changed = await switch (action) {
        _BillAction.undoPayment => _service.undoPayment(bill),
        _BillAction.archive => _service.setArchived(bill, archived: true),
        _BillAction.restore => _service.setArchived(bill, archived: false),
        _BillAction.delete => _service.deleteBill(bill),
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(changed ? success : 'The bill already has this status.'),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    } on FirebaseException catch (error) {
      debugPrint('Bill action failed (${error.code}).');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'Could not complete the action (${error.code}). '
          'Refresh the bill list to check its status before retrying.',
        )),
      );
    } catch (error) {
      debugPrint('Bill action failed (${error.runtimeType}).');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Could not complete the action. Refresh the bill list before retrying.',
        )),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Planned Bills')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('New bill'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Show paid bills'),
                    value: _showPaid,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _showPaid = value),
                  ),
                  if (_showPaid)
                    SwitchListTile(
                      title: const Text('Show archived bills'),
                      value: _showArchived,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _showArchived = value),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  Expanded(
                    child: StreamBuilder<List<PlannedBill>>(
                      stream: _billsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Could not load bills. '
                                'Check your connection and Firestore rules.',
                              ),
                            ),
                          );
                        }

                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final bills = snapshot.data!
                            .where((bill) => bill.isPaid == _showPaid &&
                                bill.archived == (_showPaid && _showArchived))
                            .toList();

                        if (bills.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _showPaid
                                    ? _showArchived
                                        ? 'No archived bills.'
                                        : 'No paid bills yet.'
                                    : 'No pending bills. Create your first bill.',
                              ),
                            ),
                          );
                        }

                        final now = DateTime.now();

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: bills.length,
                          itemBuilder: (context, index) {
                            final bill = bills[index];
                            final status = bill.status(now: now);

                            final statusLabel = switch (status) {
                              PlannedBillStatus.upcoming => 'Upcoming',
                              PlannedBillStatus.overdue => 'Overdue',
                              PlannedBillStatus.paid => 'Paid',
                            };

                            final repeatLabel =
                                bill.recurrence == BillRecurrence.monthly
                                ? 'Monthly'
                                : 'One time';

                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      bill.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(_money(bill.amountMinor)),
                                    Text('Due: ${_dateLabel(bill.dueDate)}'),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$statusLabel • $repeatLabel',
                                      style: TextStyle(
                                        color:
                                            status == PlannedBillStatus.overdue
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                            : null,
                                      ),
                                    ),
                                    if (bill.isPaid) ...[
                                      const SizedBox(height: 8),
                                      Text(bill.archived
                                          ? 'Archived • payment history retained'
                                          : 'Payment recorded • linked expense created'),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          if (bill.archived)
                                            OutlinedButton.icon(
                                              onPressed: _busy ? null
                                                  : () => _changeBill(bill, _BillAction.restore),
                                              icon: const Icon(Icons.unarchive_outlined),
                                              label: const Text('Restore'),
                                            )
                                          else ...[
                                            OutlinedButton.icon(
                                              onPressed: _busy ? null
                                                  : () => _changeBill(bill, _BillAction.undoPayment),
                                              icon: const Icon(Icons.undo),
                                              label: const Text('Undo payment'),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: _busy ? null
                                                  : () => _changeBill(bill, _BillAction.archive),
                                              icon: const Icon(Icons.archive_outlined),
                                              label: const Text('Archive'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _openEditor(bill),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            label: const Text('Edit'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _busy ? null
                                                : () => _changeBill(bill, _BillAction.delete),
                                            icon: const Icon(Icons.delete_outline),
                                            label: const Text('Delete'),
                                          ),
                                          FilledButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _markAsPaid(bill),
                                            icon: const Icon(
                                              Icons.check_circle_outline,
                                            ),
                                            label: const Text('Mark as paid'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
