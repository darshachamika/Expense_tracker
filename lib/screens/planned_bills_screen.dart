import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/planned_bill.dart';
import '../services/bill_service.dart';
import 'edit_bill_screen.dart';

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
                  'The paid bill and its linked expense cannot be '
                  'edited or deleted separately.',
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
                            .where((bill) => bill.isPaid == _showPaid)
                            .toList();

                        if (bills.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _showPaid ? 'No paid bills yet.' : 'No pending bills. Create your first bill.',
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
                                      const Text(
                                        'Payment recorded • linked expense created',
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
