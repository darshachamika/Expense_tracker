import 'package:flutter/material.dart';

import '../models/flow_profile.dart';
import '../widgets/flow_plan_preview.dart';

import '../models/expense.dart';
import '../models/monthly_budget.dart';
import '../models/monthly_expense_summary.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../widgets/spending_charts.dart';
import '../widgets/flow_home_view.dart';
import '../models/spending_period_summary.dart';
import '../widgets/period_spending_overview.dart';

enum DashboardPeriod { month, year, allTime }

class DashboardScreen extends StatefulWidget {
  final FlowProfile profile;
  final VoidCallback? onProfile,
      onCustomize,
      onAdd,
      onBudget,
      onBills,
      onGoals,
      onAdvisor;
  final String userId;
  final bool embedded;
  final String Function(String)? categoryLabel;
  final ValueChanged<Expense>? onExpense;
  final String? displayName;
  final String? photoUrl;
  final ValueChanged<DateTime>? onActivity;

  const DashboardScreen({
    super.key,
    required this.userId,
    this.embedded = false,
    this.profile = const FlowProfile(),
    this.onProfile,
    this.onCustomize,
    this.onAdd,
    this.onBudget,
    this.onBills,
    this.onGoals,
    this.onAdvisor,
    this.categoryLabel,
    this.onExpense,
    this.displayName,
    this.photoUrl,
    this.onActivity,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardPeriod _period = DashboardPeriod.month;
  late int _year;
  late DateTime _month;
  late final BudgetService _budgetService;
  late final Stream<List<Expense>> _expensesStream;
  late Stream<MonthlyBudget?> _budgetStream;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _year = now.year;

    _budgetService = BudgetService(userId: widget.userId);
    _budgetStream = _budgetService.watchBudget(_month);
    _expensesStream = ExpenseService(userId: widget.userId).watchExpenses();
  }

  void _selectMonth(DateTime month) {
    if (month.year < 2000 || month.year > 9999) return;

    final selected = DateTime(month.year, month.month);
    if (selected == _month) return;

    setState(() {
      _month = selected;
      _budgetStream = _budgetService.watchBudget(selected);
    });
  }

  void _openMonth(DateTime month) {
    if (month.year < 2000 || month.year > 9999) return;

    _selectMonth(month);
    setState(() {
      _period = DashboardPeriod.month;
      _year = month.year;
    });
  }

  Widget _buildPeriodDashboard(List<Expense> expenses) {
    final now = DateTime.now();
    final isYear = _period == DashboardPeriod.year;
    final summary = isYear
        ? SpendingPeriodSummary.forYear(
            expenses: expenses,
            year: _year,
            now: now,
          )
        : SpendingPeriodSummary.allTime(expenses: expenses, now: now);

    return ListView(
      key: ValueKey(_period),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
      children: [
        if (isYear) ...[
          Row(
            children: [
              IconButton(
                tooltip: 'Previous year',
                onPressed: _year <= 2000 ? null : () => setState(() => _year--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _year == now.year ? '$_year • Year to date' : '$_year',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Next year',
                onPressed: _year >= now.year
                    ? null
                    : () => setState(() => _year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _year = now.year),
              child: const Text('Current year'),
            ),
          ),
        ] else ...[
          Text(
            'All-time spending',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Recorded expenses from your first expense through today.',
          ),
        ],
        const SizedBox(height: 20),
        PeriodSpendingOverview(
          userId: widget.userId,
          summary: summary,
          onMonthSelected: _openMonth,
        ),
      ],
    );
  }

  Widget _buildDashboard(List<Expense> expenses) =>
      StreamBuilder<MonthlyBudget?>(
        key: ValueKey(MonthlyBudget.monthKey(_month)),
        stream: _budgetStream,
        builder: (context, snapshot) => FlowHomeView(
          profile: widget.profile,
          onProfile: widget.onProfile,
          onCustomize: widget.onCustomize,
          onAdd: widget.onAdd,
          onBudget: widget.onBudget,
          onBills: widget.onBills,
          onGoals: widget.onGoals,
          onAdvisor: widget.onAdvisor,
          planPreview: FlowPlanPreview(
            userId: widget.userId,
            onBills: widget.onBills,
            onGoals: widget.onGoals,
          ),
          expenses: expenses,
          month: _month,
          now: DateTime.now(),
          budget: snapshot.data,
          budgetLoading: snapshot.connectionState == ConnectionState.waiting,
          budgetError: snapshot.hasError,
          displayName: widget.displayName,
          photoUrl: widget.photoUrl,
          categoryLabel: widget.categoryLabel ?? (_) => 'Expense',
          onMonth: _selectMonth,
          onActivity: widget.onActivity == null
              ? null
              : () => widget.onActivity!(_month),
          onExpense: widget.onExpense,
          onAnalytics: () {
            if (widget.embedded) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DashboardScreen(
                    userId: widget.userId,
                    displayName: widget.displayName,
                    photoUrl: widget.photoUrl,
                    categoryLabel: widget.categoryLabel,
                  ),
                ),
              );
            } else {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => FractionallySizedBox(
                  heightFactor: .9,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SpendingCharts(
                      userId: widget.userId,
                      summary: MonthlyExpenseSummary.fromExpenses(
                        expenses: expenses,
                        month: _month,
                      ),
                    ),
                  ),
                ),
              );
            }
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Dashboard')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.embedded ? 480 : 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.embedded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: SegmentedButton<DashboardPeriod>(
                      segments: const [
                        ButtonSegment(
                          value: DashboardPeriod.month,
                          label: Text('Month'),
                        ),
                        ButtonSegment(
                          value: DashboardPeriod.year,
                          label: Text('Year'),
                        ),
                        ButtonSegment(
                          value: DashboardPeriod.allTime,
                          label: Text('All time'),
                        ),
                      ],
                      selected: {_period},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() => _period = selection.single);
                      },
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<Expense>>(
                    stream: _expensesStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Could not load your expenses. '
                              'Check your connection and reopen this screen.',
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final expenses = snapshot.data!;
                      return _period == DashboardPeriod.month
                          ? _buildDashboard(expenses)
                          : _buildPeriodDashboard(expenses);
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
