import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String id;
  final String title;
  final int amountMinor;
  final String categoryId;
  final String paymentMethod;
  final String note;
  final DateTime expenseDate;
  final DateTime? createdAt;

  const Expense({
    required this.id,
    required this.title,
    required this.amountMinor,
    required this.categoryId,
    required this.paymentMethod,
    required this.expenseDate,
    this.note = '',
    this.createdAt,
  });

  // Display purposes only. Calculations use amountMinor.
  double get amount => amountMinor / 100;

  // Convert a Firestore document into an Expense object.
  factory Expense.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Expense document does not exist.');
    }

    return Expense(
      id: document.id,
      title: data['title'] as String,
      amountMinor: data['amountMinor'] as int,
      categoryId: data['categoryId'] as String,
      paymentMethod: data['paymentMethod'] as String,
      note: data['note'] as String? ?? '',
      expenseDate: (data['expenseDate'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  // Fields that users can edit.
  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title.trim(),
      'amountMinor': amountMinor,
      'categoryId': categoryId,
      'paymentMethod': paymentMethod,
      'note': note.trim(),
      'expenseDate': Timestamp.fromDate(expenseDate),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // New documents also need a creation timestamp.
  Map<String, dynamic> toCreateMap() {
    return {...toUpdateMap(), 'createdAt': FieldValue.serverTimestamp()};
  }
}
