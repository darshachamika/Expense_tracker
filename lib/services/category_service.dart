import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense_category.dart';

class CategoryService {
  final String userId;
  final FirebaseFirestore _firestore;

  CategoryService({required this.userId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance {
    if (userId.trim().isEmpty || userId.contains('/')) {
      throw ArgumentError('A valid user ID is required.');
    }
  }

  CollectionReference<Map<String, dynamic>> get _categories {
    return _firestore.collection('users').doc(userId).collection('categories');
  }

  static const defaultCategories = {
    'food': 'Food & Drinks',
    'transport': 'Transport',
    'home': 'Home & Utilities',
    'shopping': 'Shopping',
    'health': 'Health & Wellness',
    'entertainment': 'Entertainment',
    'education': 'Education',
    'other': 'Other',
  };

  // Create only missing starter categories.
  // Existing names and archived states are preserved.
  Future<void> ensureDefaultCategories() async {
    final entries = defaultCategories.entries.toList();

    await _firestore.runTransaction((transaction) async {
      // Read all documents before writing any documents.
      final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final entry in entries) {
        final snapshot = await transaction.get(_categories.doc(entry.key));

        snapshots.add(snapshot);
      }

      for (var index = 0; index < entries.length; index++) {
        if (!snapshots[index].exists) {
          final entry = entries[index];

          transaction.set(_categories.doc(entry.key), {
            'name': entry.value,
            'archived': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    });
  }

  Stream<List<ExpenseCategory>> watchCategories() {
    return _categories.snapshots().map((snapshot) {
      final categories = snapshot.docs
          .map((document) => ExpenseCategory.fromFirestore(document))
          .toList();

      categories.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      return categories;
    });
  }

  Future<String> createCategory(String name) async {
    final cleanName = _validateName(name);

    final document = await _categories.add({
      'name': cleanName,
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return document.id;
  }

  Future<void> renameCategory(String id, String name) async {
    _validateId(id);
    final cleanName = _validateName(name);

    await _categories.doc(id).update({
      'name': cleanName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setArchived(String id, bool archived) async {
    _validateId(id);

    await _categories.doc(id).update({
      'archived': archived,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _validateName(String name) {
    final value = name.trim();

    if (value.isEmpty || value.length > 60) {
      throw ArgumentError('Category name must contain 1 to 60 characters.');
    }

    return value;
  }

  void _validateId(String id) {
    if (id.trim().isEmpty || id.contains('/')) {
      throw ArgumentError('A valid category ID is required.');
    }
  }
}
