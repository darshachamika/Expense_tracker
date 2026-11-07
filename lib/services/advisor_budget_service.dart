import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/budget_action.dart';
import '../models/expense_category.dart';
import '../models/monthly_budget.dart';
import 'budget_service.dart';

class AdvisorBudgetService {
  final String userId;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AdvisorBudgetService({
    required this.userId,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    if (userId.trim().isEmpty || userId.contains('/')) {
      throw ArgumentError('A valid user ID is required.');
    }
  }

  DocumentReference<Map<String, dynamic>> get _owner =>
      _firestore.collection('users').doc(userId);

  void _checkUser() {
    if (_auth.currentUser?.uid != userId) {
      throw StateError('Your session changed. Reopen the advisor.');
    }
  }

  String _normalize(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<BudgetActionPreview> preview(
    BudgetActionInput input,
    BudgetActionTarget target,
  ) async {
    _checkUser();
    final categories = _owner.collection('categories');
    ExpenseCategory? category;
    if (target.category != null) {
      final rows = await categories
          .limit(501)
          .get(const GetOptions(source: Source.server));
      if (rows.metadata.hasPendingWrites || rows.docs.length > 500) {
        throw StateError(
          'Could not verify the available categories. Try again.',
        );
      }
      final candidates = rows.docs.map(ExpenseCategory.fromFirestore).toList();
      final name = _normalize(target.category!);
      final exact = candidates
          .where((c) => _normalize(c.name) == name)
          .toList();
      final matches = exact.isNotEmpty
          ? exact
          : candidates
                .where((c) => _normalize(c.name).startsWith('$name '))
                .toList();
      if (matches.length != 1 || matches.single.archived) {
        throw StateError(
          'Use one active category name from Manage Categories.',
        );
      }
      category = matches.single;
    }
    _checkUser();
    final doc = await _owner
        .collection('budgets')
        .doc(MonthlyBudget.monthKey(input.month))
        .get(const GetOptions(source: Source.server));
    _checkUser();
    if (doc.metadata.hasPendingWrites) {
      throw StateError('Budget changes are syncing. Try again shortly.');
    }
    final budget = doc.exists ? MonthlyBudget.fromFirestore(doc) : null;
    if (category != null && budget == null) {
      throw StateError(
        'Set the overall monthly budget first, then add the category limit.',
      );
    }
    return BudgetActionPreview(
      userId: userId,
      month: input.month,
      categoryId: category?.id,
      categoryName: category?.name,
      previousMinor: category == null
          ? budget?.overallLimitMinor
          : budget?.categoryLimitsMinor[category.id],
      proposedMinor: input.amountMinor,
    );
  }

  /// Returns true for a committed change and false when already applied.
  Future<bool> confirm(BudgetActionPreview preview) async {
    _checkUser();
    final categoryId = preview.categoryId;
    if (preview.userId != userId ||
        preview.month.year < 2000 ||
        preview.month.year > 9999 ||
        preview.proposedMinor <= 0 ||
        preview.proposedMinor > BudgetService.maxAmountMinor ||
        (categoryId != null &&
            (categoryId.trim().isEmpty ||
                categoryId.length > 100 ||
                categoryId.contains('/')))) {
      throw StateError('This budget preview is invalid. Prepare it again.');
    }
    final reference = _owner.collection('budgets').doc(preview.monthKey);
    return _firestore.runTransaction<bool>((transaction) async {
      _checkUser();
      final doc = await transaction.get(reference);
      final budget = doc.exists ? MonthlyBudget.fromFirestore(doc) : null;
      if (categoryId != null) {
        final categoryDoc = await transaction.get(
          _owner.collection('categories').doc(categoryId),
        );
        if (!categoryDoc.exists || budget == null) {
          throw const BudgetPreviewChanged();
        }
        final category = ExpenseCategory.fromFirestore(categoryDoc);
        if (category.archived || category.name != preview.categoryName) {
          throw const BudgetPreviewChanged();
        }
      }
      _checkUser();
      final current = categoryId == null
          ? budget?.overallLimitMinor
          : budget?.categoryLimitsMinor[categoryId];
      if (current == preview.proposedMinor) return false;
      if (current != preview.previousMinor) throw const BudgetPreviewChanged();
      final limits = <String, int>{...?budget?.categoryLimitsMinor};
      if (categoryId != null) limits[categoryId] = preview.proposedMinor;
      if (limits.length > BudgetService.maxCategoryLimits) {
        throw StateError('This month has reached its category limit count.');
      }
      final updated = MonthlyBudget(
        id: reference.id,
        overallLimitMinor: categoryId == null
            ? preview.proposedMinor
            : budget!.overallLimitMinor,
        categoryLimitsMinor: limits,
      );
      if (doc.exists) {
        transaction.update(reference, updated.toUpdateMap());
      } else {
        transaction.set(reference, updated.toCreateMap());
      }
      return true;
    });
  }
}
