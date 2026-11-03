import 'package:flutter/material.dart';

import '../models/savings_goal.dart';
import '../services/savings_service.dart';
import 'edit_savings_goal_screen.dart';
import 'savings_goal_details_screen.dart';

class SavingsGoalsScreen extends StatefulWidget {
  final String userId;

  const SavingsGoalsScreen({super.key, required this.userId});

  @override
  State<SavingsGoalsScreen> createState() => _SavingsGoalsScreenState();
}

class _SavingsGoalsScreenState extends State<SavingsGoalsScreen> {
  late final SavingsService _service;
  late final Stream<List<SavingsGoal>> _goalsStream;

  bool _showArchived = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _service = SavingsService(userId: widget.userId);
    _goalsStream = _service.watchGoals();
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Savings Goals')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('New goal'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Show archived goals'),
                    value: _showArchived,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _showArchived = value),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  Expanded(
                    child: StreamBuilder<List<SavingsGoal>>(
                      stream: _goalsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Could not load savings goals. '
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

                        final goals = snapshot.data!
                            .where((goal) => goal.archived == _showArchived)
                            .toList();

                        if (goals.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _showArchived
                                    ? 'No archived goals.'
                                    : 'Create your first savings goal.',
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: goals.length,
                          itemBuilder: (context, index) {
                            final goal = goals[index];

                            return Card(
                              child: ListTile(
                                onTap: _busy
                                    ? null
                                    : () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                SavingsGoalDetailsScreen(
                                                  userId: widget.userId,
                                                  goalId: goal.id,
                                                ),
                                          ),
                                        );
                                      },
                                contentPadding: const EdgeInsets.all(16),
                                leading: const Icon(Icons.flag_outlined),
                                title: Text(goal.title),
                                subtitle: Text(
                                  'Target: ${_money(goal.targetMinor)}\n'
                                  '${goal.targetDate == null ? 'No deadline' : 'Target date: ${_dateLabel(goal.targetDate!)}'}',
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  enabled: !_busy,
                                  onSelected: (action) {
                                    if (action == 'edit') {
                                      _openEditor(goal);
                                    } else if (action == 'archive') {
                                      _toggleArchive(goal);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit goal'),
                                    ),
                                    PopupMenuItem(
                                      value: 'archive',
                                      child: Text(
                                        goal.archived ? 'Restore' : 'Archive',
                                      ),
                                    ),
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
