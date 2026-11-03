import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_budget.dart';

class BudgetService {
  final String userId;
  final FirebaseFirestore _firestore;

  static const int maxAmountMinor = 99999999999;
  static const int maxCategoryLimits = 100;

  BudgetService({required this.userId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance {
    if (userId.isEmpty || userId.contains('/')) {
      throw ArgumentError('A valid user ID is required.');
    }
  }

  CollectionReference<Map<String, dynamic>> get _collection {
    return _firestore.collection('users').doc(userId).collection('budgets');
  }

  DocumentReference<Map<String, dynamic>> _document(DateTime month) {
    if (month.year < 2000 || month.year > 9999) {
      throw ArgumentError('Budget year must be between 2000 and 9999.');
    }

    return _collection.doc(MonthlyBudget.monthKey(month));
  }

  Stream<MonthlyBudget?> watchBudget(DateTime month) {
    return _document(month).snapshots().map((document) {
      if (!document.exists) return null;

      return MonthlyBudget.fromFirestore(document);
    });
  }

  /// Saves the complete budget configuration for the selected month.
  ///
  /// Existing category limits omitted from this map are removed.
  Future<void> saveBudget({
    required DateTime month,
    required int overallLimitMinor,
    Map<String, int> categoryLimitsMinor = const {},
  }) async {
    _validateAmount(overallLimitMinor);

    if (categoryLimitsMinor.length > maxCategoryLimits) {
      throw ArgumentError(
        'A monthly budget supports up to $maxCategoryLimits categories.',
      );
    }

    for (final entry in categoryLimitsMinor.entries) {
      if (entry.key.trim().isEmpty ||
          entry.key.length > 100 ||
          entry.key.contains('/')) {
        throw ArgumentError('Invalid category ID.');
      }

      _validateAmount(entry.value);
    }

    final reference = _document(month);

    final budget = MonthlyBudget(
      id: reference.id,
      overallLimitMinor: overallLimitMinor,
      categoryLimitsMinor: categoryLimitsMinor,
    );

    await _firestore.runTransaction<void>((transaction) async {
      final existing = await transaction.get(reference);

      if (existing.exists) {
        transaction.update(reference, budget.toUpdateMap());
      } else {
        transaction.set(reference, budget.toCreateMap());
      }
    });
  }

  Future<void> deleteBudget(DateTime month) async {
    await _document(month).delete();
  }

  void _validateAmount(int amountMinor) {
    if (amountMinor <= 0 || amountMinor > maxAmountMinor) {
      throw ArgumentError(
        'Budget amount must be positive and within the supported range.',
      );
    }
  }
}
