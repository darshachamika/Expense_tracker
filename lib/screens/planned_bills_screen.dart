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
  late final Stream<List<PlannedBill>> _billsStream;
  bool _showPaid = false;

  @override
  void initState() {
    super.initState();

    _billsStream = BillService(userId: widget.userId).watchBills();
  }

  Future<void> _openEditor([PlannedBill? bill]) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planned Bills')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
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
                  onChanged: (value) {
                    setState(() => _showPaid = value);
                  },
                ),
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
                        return const Center(child: CircularProgressIndicator());
                      }

                      final bills = snapshot.data!
                          .where((bill) => bill.isPaid == _showPaid)
                          .toList();

                      if (bills.isEmpty) {
                        return Center(
                          child: Text(
                            _showPaid
                                ? 'No paid bills yet.'
                                : 'No pending bills. Create your first bill.',
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
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              onTap: bill.isPaid
                                  ? null
                                  : () => _openEditor(bill),
                              leading: Icon(
                                bill.isPaid
                                    ? Icons.check_circle_outline
                                    : Icons.receipt_long_outlined,
                                color: status == PlannedBillStatus.overdue
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                              title: Text(bill.title),
                              subtitle: Text(
                                '${_money(bill.amountMinor)}\n'
                                'Due: ${_dateLabel(bill.dueDate)}\n'
                                '$statusLabel • $repeatLabel',
                              ),
                              trailing: bill.isPaid
                                  ? null
                                  : const Icon(Icons.edit_outlined),
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
    );
  }
}
