import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/expense.dart';
import '../models/expense_action.dart';
import '../models/expense_category.dart';

class AdvisorExpenseService {
  final String userId;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AdvisorExpenseService({
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

  Future<ExpenseActionPreview> preview(
    ExpenseActionInput input,
    ExpenseActionPlan plan,
  ) async {
    _checkUser();
    final rows = await _owner.collection('categories').limit(501)
        .get(const GetOptions(source: Source.server));
    _checkUser();
    if (rows.metadata.hasPendingWrites || rows.docs.length > 500) {
      throw StateError('Could not verify categories. Try again shortly.');
    }
    final categories = rows.docs.map(ExpenseCategory.fromFirestore).toList();
    final name = _normalize(plan.category);
    final exact = categories.where((c) => _normalize(c.name) == name).toList();
    final matches = exact.isNotEmpty ? exact : categories
        .where((c) => _normalize(c.name).startsWith('$name ')).toList();
    if (matches.length != 1 || matches.single.archived) {
      throw StateError('Use one active category name from Manage Categories.');
    }
    final category = matches.single;
    // Allocating a document ID makes no write. Retain it for every retry.
    final id = 'advisor_${_owner.collection('expenses').doc().id}';
    final preview = ExpenseActionPreview(
      userId: userId,
      expense: Expense(
        id: id,
        title: plan.title,
        amountMinor: input.amountMinor,
        categoryId: category.id,
        paymentMethod: plan.paymentMethod,
        expenseDate: input.date,
      ),
      categoryName: category.name,
      defaultPayment: plan.defaultPayment,
      defaultDate: !input.explicitDate,
    );
    preview.validate(userId, DateTime.now());
    return preview;
  }

  /// False means this preview was already saved, including a lost response.
  Future<bool> confirm(ExpenseActionPreview preview) async {
    _checkUser();
    preview.validate(userId, DateTime.now());
    final expense = preview.expense;
    final reference = _owner.collection('expenses').doc(expense.id);
    return _firestore.runTransaction<bool>((transaction) async {
      _checkUser();
      final existing = await transaction.get(reference);
      if (existing.exists) {
        _checkUser();
        // Never replace a record that was edited after an earlier save.
        return false;
      }
      final categoryDoc = await transaction.get(
        _owner.collection('categories').doc(expense.categoryId),
      );
      _checkUser();
      if (!categoryDoc.exists) throw const ExpensePreviewChanged();
      final category = ExpenseCategory.fromFirestore(categoryDoc);
      if (category.archived || category.name != preview.categoryName) {
        throw const ExpensePreviewChanged();
      }
      transaction.set(reference, expense.toCreateMap());
      return true;
    });
  }
}
