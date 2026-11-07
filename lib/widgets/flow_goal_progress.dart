import 'package:flutter/material.dart';
import '../models/savings_goal.dart';
import '../models/savings_contribution.dart';
import '../services/savings_service.dart';

/// Keep the subscription stable while the parent list rebuilds.
class FlowGoalProgress extends StatefulWidget {
  final SavingsGoal goal;
  final SavingsService service;
  const FlowGoalProgress({super.key, required this.goal, required this.service});
  @override
  State<FlowGoalProgress> createState() => _FlowGoalProgressState();
}
class _FlowGoalProgressState extends State<FlowGoalProgress> {
  late Stream<List<SavingsContribution>> _stream;
  @override
  void initState() { super.initState(); _stream = widget.service.watchContributions(widget.goal.id); }
  @override
  void didUpdateWidget(covariant FlowGoalProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.goal.id != oldWidget.goal.id || widget.service != oldWidget.service) {
      _stream = widget.service.watchContributions(widget.goal.id);
    }
  }
  String _money(int minor) => 'Rs. ${(minor / 100).toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) => StreamBuilder<List<SavingsContribution>>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Could not load savings progress.');
      if (!snapshot.hasData) return const Text('Loading savings…');
      final saved = snapshot.data!.fold<int>(0, (sum, item) => sum + item.amountMinor);
      final progress = widget.goal.progress(saved);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${_money(saved)} / ${_money(widget.goal.targetMinor)}'),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: progress, minHeight: 8),
        const SizedBox(height: 6),
        Text('${(progress * 100).round()}% saved'),
      ]);
    },
  );
}
