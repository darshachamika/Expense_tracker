import 'dart:async';

import 'package:flutter/material.dart';

import '../models/savings_goal.dart';
import '../theme/flow_theme.dart';
import 'flow_format.dart';

class FlowGoalSavingsPlan extends StatefulWidget {
  final SavingsGoal goal;
  final int savedMinor;

  const FlowGoalSavingsPlan({
    super.key,
    required this.goal,
    required this.savedMinor,
  });

  @override
  State<FlowGoalSavingsPlan> createState() => _FlowGoalSavingsPlanState();
}

class _FlowGoalSavingsPlanState extends State<FlowGoalSavingsPlan> {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _dayTimer;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _refreshDate);
    _scheduleDateRefresh();
  }

  void _scheduleDateRefresh() {
    _dayTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(tomorrow.difference(now), _refreshDate);
  }

  void _refreshDate() {
    if (!mounted) return;
    setState(() {});
    _scheduleDateRefresh();
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = widget.goal;
    final saved = widget.savedMinor;
    final now = DateTime.now();
    final months = goal.savingMonthsLeft(now: now);
    final monthly = goal.monthlyRequiredMinor(savedMinor: saved, now: now);
    final remaining = FlowFormat.money(goal.remainingMinor(saved));

    if (goal.isCompleted(saved)) {
      return const _PlanPanel(
        icon: Icons.check_circle_outline_rounded,
        label: 'Goal reached',
      );
    }
    if (goal.targetDate == null) {
      return _PlanPanel(
        icon: Icons.event_outlined,
        label: '$remaining left to save',
        description: 'Set a target date to see your monthly amount.',
      );
    }
    if (months == null || monthly == null) {
      return _PlanPanel(
        icon: Icons.schedule_rounded,
        label: 'Overdue',
        description: '$remaining left to save. Edit the target date to replan.',
        accent: theme.colorScheme.error,
      );
    }

    final nextYear = months > 12
        ? goal.nextTwelveMonthsRequiredMinor(savedMinor: saved, now: now)
        : null;
    final monthLabel = months == 1 ? 'saving month' : 'saving months';

    return _PlanPanel(
      icon: Icons.route_rounded,
      label: 'Savings plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                FlowFormat.money(monthly),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('per month', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$months $monthLabel left, including this month',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _PlanAmount(label: 'Left to save', amount: remaining),
          if (nextYear != null)
            _PlanAmount(
              label: 'Next 12 months',
              amount: FlowFormat.money(nextYear),
            ),
        ],
      ),
    );
  }
}

class _PlanPanel extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final Color? accent;
  final Widget? child;

  const _PlanPanel({
    required this.icon,
    required this.label,
    this.description,
    this.accent,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final highlight = accent ?? (dark ? const Color(0xFF77E7F8) : FlowTheme.blue);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF183656), Color(0xFF10233F)]
              : const [Color(0xFFE7F7FF), Color(0xFFF7FBFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight.withValues(alpha: .30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: highlight.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(icon, size: 17, color: highlight),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: highlight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(description!, style: theme.textTheme.bodySmall),
          ],
          if (child != null) ...[
            const SizedBox(height: 8),
            child!,
          ],
        ],
      ),
    );
  }
}

class _PlanAmount extends StatelessWidget {
  final String label;
  final String amount;

  const _PlanAmount({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              amount,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
