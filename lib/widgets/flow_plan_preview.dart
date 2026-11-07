import 'package:flutter/material.dart';

import '../models/planned_bill.dart';
import '../models/savings_goal.dart';
import '../services/bill_service.dart';
import '../services/savings_service.dart';
import 'flow_format.dart';
import 'flow_goal_progress.dart';

class FlowPlanPreview extends StatefulWidget {
  final String userId;
  final VoidCallback? onBills, onGoals;
  const FlowPlanPreview({
    super.key,
    required this.userId,
    this.onBills,
    this.onGoals,
  });
  @override
  State<FlowPlanPreview> createState() => _FlowPlanPreviewState();
}

class _FlowPlanPreviewState extends State<FlowPlanPreview> {
  late final _bills = BillService(userId: widget.userId).watchBills();
  late final _savings = SavingsService(userId: widget.userId);
  late final _goals = _savings.watchGoals();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StreamBuilder<List<PlannedBill>>(
        stream: _bills,
        builder: (context, snapshot) {
          final bills =
              snapshot.data?.where((b) => !b.archived && !b.isPaid).toList() ??
              [];
          bills.sort((a, b) => a.dueDate.compareTo(b.dueDate));
          final bill = bills.firstOrNull;
          return Card(
            child: ListTile(
              leading: const Icon(
                Icons.receipt_long_outlined,
                color: Color(0xFF075BEE),
              ),
              title: Text(
                snapshot.hasError
                    ? 'Bills unavailable'
                    : !snapshot.hasData
                    ? 'Loading bills…'
                    : bill?.title ?? 'No upcoming bills',
              ),
              subtitle: Text(
                bill == null
                    ? 'Plan your upcoming payments'
                    : '${bill.status() == PlannedBillStatus.overdue ? 'Overdue' : 'Due'} ${FlowFormat.shortDate(bill.dueDate)} • ${FlowFormat.money(bill.amountMinor)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onBills,
            ),
          );
        },
      ),
      StreamBuilder<List<SavingsGoal>>(
        stream: _goals,
        builder: (context, snapshot) {
          final goal = snapshot.data?.where((g) => !g.archived).firstOrNull;
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: widget.onGoals,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.flag_outlined,
                          color: Color(0xFF075BEE),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            snapshot.hasError
                                ? 'Goals unavailable'
                                : !snapshot.hasData
                                ? 'Loading goals…'
                                : goal?.title ?? 'Start a savings goal',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    if (goal != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: FlowGoalProgress(
                          key: ValueKey(goal.id),
                          goal: goal,
                          service: _savings,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}
