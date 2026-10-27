import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense.dart';

class ExpenseService {
  final String userId;
  final FirebaseFirestore _firestore;

  ExpenseService({required this.userId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance {
    if (userId.trim().isEmpty || userId.contains('/')) {
      throw ArgumentError('A valid user ID is required.');
    }
  }

  CollectionReference<Map<String, dynamic>> get _expenses {
    return _firestore.collection('users').doc(userId).collection('expenses');
  }

  // CREATE: save an expense and return its document ID.
  Future<String> createExpense(Expense expense) async {
    _validateExpense(expense);

    final document = await _expenses.add(expense.toCreateMap());

    return document.id;
  }

  // READ: receive updates whenever expenses change.
  Stream<List<Expense>> watchExpenses() {
    return _expenses
        .orderBy('expenseDate', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) => Expense.fromFirestore(document))
              .toList(),
        );
  }

  // UPDATE: edit an existing expense.
  Future<void> updateExpense(Expense expense) async {
    _validateDocumentId(expense.id);
    _validateExpense(expense);

    await _expenses.doc(expense.id).update(expense.toUpdateMap());
  }

  // DELETE: remove an expense by document ID.
  Future<void> deleteExpense(String expenseId) async {
    _validateDocumentId(expenseId);

    await _expenses.doc(expenseId).delete();
  }

  void _validateExpense(Expense expense) {
    if (expense.title.trim().isEmpty) {
      throw ArgumentError('Expense title is required.');
    }

    if (expense.amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero.');
    }

    if (expense.categoryId.trim().isEmpty) {
      throw ArgumentError('Category is required.');
    }

    const paymentMethods = {'cash', 'card', 'bank'};

    if (!paymentMethods.contains(expense.paymentMethod)) {
      throw ArgumentError('Invalid payment method.');
    }
  }

  void _validateDocumentId(String id) {
    if (id.trim().isEmpty || id.contains('/')) {
      throw ArgumentError('A valid expense ID is required.');
    }
  }
}
