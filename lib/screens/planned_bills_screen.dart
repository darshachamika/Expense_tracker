import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/flow_visuals.dart';
import '../widgets/flow_format.dart';

import '../models/planned_bill.dart';
import '../services/bill_service.dart';
import 'edit_bill_screen.dart';

enum _BillAction { undoPayment, archive, restore, delete }

class PlannedBillsScreen extends StatefulWidget {
  final String userId;
  final VoidCallback? onOpenAdvisor;
  final ValueChanged<int>? onNavigate;

  const PlannedBillsScreen({super.key, required this.userId, this.onOpenAdvisor, this.onNavigate});

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

  Widget _billCard(PlannedBill bill) {
    final overdue = bill.status() == PlannedBillStatus.overdue;
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FlowCategoryIcon(category: bill.title.toLowerCase().contains('water') ? 'water' : bill.title.toLowerCase().contains('internet') ? 'internet' : 'electricity'),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(bill.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 5),
        Text(bill.isPaid ? 'Paid ${FlowFormat.shortDate(bill.paidAt!.toLocal())}' : 'Due ${FlowFormat.shortDate(bill.dueDate.toLocal())}', style: TextStyle(fontSize: 12, color: overdue ? Theme.of(context).colorScheme.error : const Color(0xFF53627D))),
        if (overdue) const Text('Overdue', style: TextStyle(color: Colors.red, fontSize: 11)),
        if (bill.recurrence == BillRecurrence.monthly) const Text('Monthly', style: TextStyle(fontSize: 11, color: Color(0xFF53627D))),
        if (bill.isPaid) Padding(padding: const EdgeInsets.only(top: 6), child: Text(bill.archived ? 'Archived • history retained' : '✓ Paid', style: const TextStyle(color: Color(0xFF008879), fontSize: 12, fontWeight: FontWeight.w700))),
      ])),
      const SizedBox(width: 8),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(FlowFormat.money(bill.amountMinor), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (!bill.isPaid) ...[const SizedBox(height: 8), FilledButton(onPressed: _busy ? null : () => _markAsPaid(bill), style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)), child: const Text('Mark paid', style: TextStyle(fontSize: 12)))],
        PopupMenuButton<String>(enabled: !_busy, tooltip: 'Bill actions',
          onSelected: (action) {
            if (action == 'edit') { _openEditor(bill); }
            else if (action == 'delete') { _changeBill(bill, _BillAction.delete); }
            else if (action == 'undo') { _changeBill(bill, _BillAction.undoPayment); }
            else if (action == 'archive') { _changeBill(bill, _BillAction.archive); }
            else if (action == 'restore') { _changeBill(bill, _BillAction.restore); }
          },
          itemBuilder: (_) => [
            if (!bill.isPaid) ...[const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'delete', child: Text('Delete'))],
            if (bill.isPaid && !bill.archived) ...[const PopupMenuItem(value: 'undo', child: Text('Undo payment')), const PopupMenuItem(value: 'archive', child: Text('Archive'))],
            if (bill.archived) const PopupMenuItem(value: 'restore', child: Text('Restore')),
          ],
        ),
      ])),
    ])));
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: const Text('Bills')),
    bottomNavigationBar: widget.onNavigate == null ? null : FlowBottomNav(selectedIndex: 2, onSelected: _busy ? null : widget.onNavigate),
    floatingActionButtonLocation: const FlowFabLocation(),
    floatingActionButton: FlowActions(onAdvisor: widget.onOpenAdvisor, primary: FloatingActionButton(onPressed: _busy ? null : () => _openEditor(), tooltip: 'New bill', child: const Icon(Icons.add))),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), child: SizedBox(width: double.infinity, child: SegmentedButton<int>(
        segments: const [ButtonSegment(value: 0, label: Text('Upcoming')), ButtonSegment(value: 1, label: Text('Paid')), ButtonSegment(value: 2, label: Text('Archived'))],
        selected: {_showArchived ? 2 : _showPaid ? 1 : 0}, showSelectedIcon: false,
        onSelectionChanged: _busy ? null : (selection) => setState(() { _showPaid = selection.single != 0; _showArchived = selection.single == 2; }),
      ))),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: StreamBuilder<List<PlannedBill>>(stream: _billsStream, builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Could not load bills. Check your connection and Firestore rules.')));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final bills = snapshot.data!.where((bill) => bill.isPaid == _showPaid && bill.archived == (_showPaid && _showArchived)).toList()..sort((a, b) => _showPaid ? b.paidAt!.compareTo(a.paidAt!) : a.dueDate.compareTo(b.dueDate));
        final recent = snapshot.data!.where((bill) => bill.isPaid && !bill.archived).toList()..sort((a, b) => b.paidAt!.compareTo(a.paidAt!));
        return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 130), children: [
          FlowLiquidCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_showArchived ? 'Archived payments' : _showPaid ? 'Paid bills' : 'Upcoming payments', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12), Text(FlowFormat.money(bills.fold<int>(0, (sum, bill) => sum + bill.amountMinor)), style: const TextStyle(color: Colors.white, fontSize: 33, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8), Text('${bills.length} bills in this view'),
          ])),
          const SizedBox(height: 16),
          if (bills.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No bills in this view.')),
          ...bills.map(_billCard),
          if (!_showPaid && recent.isNotEmpty) ...[
            const SizedBox(height: 20), const Text('Recently paid', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ...recent.take(3).map(_billCard),
          ],
        ]);
      })),
    ])))),
  ));
}
