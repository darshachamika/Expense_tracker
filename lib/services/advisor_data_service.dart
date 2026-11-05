import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/advisor_snapshot.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/monthly_budget.dart';
import '../models/planned_bill.dart';
import '../models/savings_contribution.dart';
import '../models/savings_goal.dart';

/// Reads only. Server reads deliberately fail offline instead of advising from
/// a potentially incomplete cache. Existing write services are not used here.
class AdvisorDataService {
  final String userId;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AdvisorDataService({
    required this.userId,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    if (userId.trim().isEmpty || userId.contains('/')) {
      throw ArgumentError('A valid user ID is required.');
    }
  }

  void _checkUser() {
    if (_auth.currentUser?.uid != userId) {
      throw StateError(
        'Your session changed. Reopen the advisor after signing in.',
      );
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _read(
    Query<Map<String, dynamic>> query,
    int maximum,
  ) async {
    final safeMaximum = maximum > 9999 ? 9999 : maximum;

    final result = await query
        .limit(safeMaximum + 1)
        .get(const GetOptions(source: Source.server));

    if (result.docs.length > safeMaximum) {
      throw StateError(
        'There is too much data for this advisor version. '
        'No incomplete summary was sent.',
      );
    }

    if (result.metadata.hasPendingWrites) {
      throw StateError('Some changes are still syncing. Wait and try again.');
    }

    return result;
  }

  Future<AdvisorSnapshot> load() async {
    _checkUser();
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);
    final nextMonth = DateTime(now.year, now.month + 1);
    final user = _firestore.collection('users').doc(userId);
    final budgetFuture = user
        .collection('budgets')
        .doc(MonthlyBudget.monthKey(now))
        .get(const GetOptions(source: Source.server));
    // All operations get handlers immediately; no unhandled errors from an
    // independently started future if another request fails first.
    final results = await Future.wait<Object>([
      _read(
        user
            .collection('expenses')
            .where(
              'expenseDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(previousMonth),
            )
            .where('expenseDate', isLessThan: Timestamp.fromDate(nextMonth)),
        10000,
      ),
      _read(user.collection('categories'), 500),
      _read(
        user
            .collection('plannedBills')
            .where('dueDate', isLessThan: Timestamp.fromDate(nextMonth)),
        2000,
      ),
      _read(
        user.collection('savingsGoals').where('archived', isEqualTo: false),
        50,
      ),
      budgetFuture,
    ]);
    final expenses = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final categories = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final bills = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final goalsResult = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final budgetResult = results[4] as DocumentSnapshot<Map<String, dynamic>>;
    if (budgetResult.metadata.hasPendingWrites) {
      throw StateError('Budget changes are still syncing. Try again shortly.');
    }
    final goals = goalsResult.docs.map(SavingsGoal.fromFirestore).toList();
    // Small batches avoid opening a request for every goal simultaneously.
    final saved = <String, int>{};
    for (var offset = 0; offset < goals.length; offset += 5) {
      _checkUser();
      final group = goals.skip(offset).take(5).toList();
      final totals = await Future.wait<int>(
        group.map((goal) async {
          final contributions = await _read(
            user
                .collection('savingsGoals')
                .doc(goal.id)
                .collection('contributions'),
            5000,
          );
          return contributions.docs
              .map(SavingsContribution.fromFirestore)
              .fold<int>(
                0,
                (sum, contribution) => sum + contribution.amountMinor,
              );
        }),
      );
      for (var index = 0; index < group.length; index++) {
        saved[group[index].id] = totals[index];
      }
    }
    _checkUser();
    return AdvisorSnapshot.calculate(
      now: now,
      expenses: expenses.docs.map(Expense.fromFirestore).toList(),
      categories: categories.docs.map(ExpenseCategory.fromFirestore).toList(),
      bills: bills.docs.map(PlannedBill.fromFirestore).toList(),
      goals: goals,
      savedByGoal: saved,
      budget: budgetResult.exists
          ? MonthlyBudget.fromFirestore(budgetResult)
          : null,
    );
  }
}
