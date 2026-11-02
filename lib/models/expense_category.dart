import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseCategory {
  final String id;
  final String name;
  final bool archived;

  const ExpenseCategory({
    required this.id,
    required this.name,
    this.archived = false,
  });

  factory ExpenseCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Category document does not exist.');
    }

    return ExpenseCategory(
      id: document.id,
      name: data['name'] as String,
      archived: data['archived'] as bool,
    );
  }
}
