import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/flow_visuals.dart';

import '../models/savings_goal.dart';
import '../models/savings_contribution.dart';
import '../widgets/flow_format.dart';
import '../widgets/flow_goal_savings_plan.dart';
import '../services/savings_service.dart';
import 'edit_savings_goal_screen.dart';
import 'savings_goal_details_screen.dart';

class SavingsGoalsScreen extends StatefulWidget {
  final String userId;
  final VoidCallback? onOpenAdvisor;
  final ValueChanged<int>? onNavigate;

  const SavingsGoalsScreen({super.key, required this.userId, this.onOpenAdvisor, this.onNavigate});

  @override
  State<SavingsGoalsScreen> createState() => _SavingsGoalsScreenState();
}

class _SavingsGoalsScreenState extends State<SavingsGoalsScreen> {
  late final SavingsService _service;
  late final Stream<List<SavingsGoal>> _goalsStream;

  final Map<String, StreamSubscription<List<SavingsContribution>>> _progressSubscriptions = {};
  final Map<String, int> _savedByGoal = {};
  final Set<String> _progressErrors = {};
  bool _showArchived = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _service = SavingsService(userId: widget.userId);
    _goalsStream = _service.watchGoals().map((goals) {
      _syncProgress(goals);
      return goals;
    });
  }

  void _syncProgress(List<SavingsGoal> goals) {
    final ids = goals.map((goal) => goal.id).toSet();
    for (final id in _progressSubscriptions.keys.where((id) => !ids.contains(id)).toList()) {
      unawaited(_progressSubscriptions.remove(id)!.cancel());
      _savedByGoal.remove(id);
      _progressErrors.remove(id);
    }
    for (final goal in goals) {
      if (_progressSubscriptions.containsKey(goal.id)) continue;
      _progressSubscriptions[goal.id] = _service.watchContributions(goal.id).listen((items) {
        if (!mounted) return;
        setState(() {
          _savedByGoal[goal.id] = items.fold<int>(0, (sum, value) => sum + value.amountMinor);
          _progressErrors.remove(goal.id);
        });
      }, onError: (Object error, StackTrace stack) {
        if (mounted) setState(() => _progressErrors.add(goal.id));
      });
    }
  }
  @override
  void dispose() {
    for (final subscription in _progressSubscriptions.values) { unawaited(subscription.cancel()); }
    super.dispose();
  }
  void _openGoal(SavingsGoal goal) {
    if (_busy) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SavingsGoalDetailsScreen(userId: widget.userId, goalId: goal.id)));
  }

  Future<void> _openEditor([SavingsGoal? goal]) async {
    if (_busy) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EditSavingsGoalScreen(userId: widget.userId, goal: goal),
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Savings goal saved.')));
    }
  }

  Future<void> _toggleArchive(SavingsGoal goal) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await _service.setArchived(goal.id, !goal.archived);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goal.archived ? 'Goal restored.' : 'Goal archived.'),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Goal archive change failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the goal.')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _goalCard(SavingsGoal goal) {
    final saved = _savedByGoal[goal.id];
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FlowCategoryIcon(category: goal.title), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(goal.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_progressErrors.contains(goal.id) ? 'Progress unavailable' : saved == null ? 'Loading savings…' : '${FlowFormat.money(saved)} / ${FlowFormat.money(goal.targetMinor)}', style: const TextStyle(fontSize: 12)),
        ])),
        PopupMenuButton<String>(enabled: !_busy, tooltip: 'Goal actions', onSelected: (action) => action == 'edit' ? _openEditor(goal) : _toggleArchive(goal),
          itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit goal')), PopupMenuItem(value: 'archive', child: Text(goal.archived ? 'Restore' : 'Archive'))]),
      ]),
      if (saved != null && !_progressErrors.contains(goal.id)) ...[
        const SizedBox(height: 14), LinearProgressIndicator(value: goal.progress(saved), minHeight: 8),
        const SizedBox(height: 8), Text('${(goal.progress(saved) * 100).round()}% saved', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
      if (goal.targetDate != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Target ${FlowFormat.shortDate(goal.targetDate!)} ${goal.targetDate!.year}', style: const TextStyle(fontSize: 11))),
      if (!goal.archived && saved != null && !_progressErrors.contains(goal.id)) ...[
        const SizedBox(height: 12),
        FlowGoalSavingsPlan(
          key: ValueKey(goal.id),
          goal: goal,
          savedMinor: saved,
        ),
      ],
      const SizedBox(height: 12),
      FilledButton.tonalIcon(onPressed: _busy ? null : () => _openGoal(goal), icon: Icon(goal.archived ? Icons.history : Icons.add), label: Text(goal.archived ? 'View savings' : 'Add savings')),
    ])));
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: const Text('Goals')),
    bottomNavigationBar: widget.onNavigate == null ? null : FlowBottomNav(selectedIndex: 2, onSelected: _busy ? null : widget.onNavigate),
    floatingActionButtonLocation: const FlowFabLocation(),
    floatingActionButton: FlowActions(onAdvisor: widget.onOpenAdvisor, primary: FloatingActionButton(onPressed: _busy ? null : () => _openEditor(), tooltip: 'New goal', child: const Icon(Icons.add))),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), child: SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Active')), ButtonSegment(value: true, label: Text('Archived'))], selected: {_showArchived}, showSelectedIcon: false, onSelectionChanged: _busy ? null : (selection) => setState(() => _showArchived = selection.single))),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: StreamBuilder<List<SavingsGoal>>(stream: _goalsStream, builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Could not load savings goals. Check your connection and Firestore rules.')));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final goals = snapshot.data!.where((goal) => goal.archived == _showArchived).toList();
        final failed = goals.any((goal) => _progressErrors.contains(goal.id));
        final loading = goals.any((goal) => !_savedByGoal.containsKey(goal.id));
        final total = goals.fold<int>(0, (sum, goal) => sum + (_savedByGoal[goal.id] ?? 0));
        return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 130), children: [
          FlowLiquidCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_showArchived ? 'Saved in archived goals' : 'Saved towards your goals', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(failed ? 'Progress unavailable' : loading ? 'Loading savings…' : FlowFormat.money(total), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10), const Text('Small steps. Real progress.'),
          ])),
          const SizedBox(height: 18),
          if (goals.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No goals here yet. Tap + to create one.')),
          ...goals.map(_goalCard),
          const SizedBox(height: 12), const Text('ⓘ Contributions stay separate from spending.', style: TextStyle(fontSize: 12, color: Color(0xFF53627D))),
        ]);
      })),
    ])))),
  ));
}
