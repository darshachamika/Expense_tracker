import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/category_action.dart';
import '../models/expense_category.dart';

/// The one write capability in this feature. Called only by Confirm, never by
/// Gemini or by the planning/preview flow. Existing category services are intact.
class AdvisorCategoryService {
  final String userId;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AdvisorCategoryService({
    required this.userId,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    if (userId.trim().isEmpty || userId.contains('/')) {
      throw ArgumentError('A valid user ID is required.');
    }
  }

  CollectionReference<Map<String, dynamic>> get _categories =>
      _firestore.collection('users').doc(userId).collection('categories');

  void _checkUser() {
    if (_auth.currentUser?.uid != userId) {
      throw StateError('Your session changed. Reopen the advisor.');
    }
  }

  Future<CategoryActionResult?> findExisting(String name) async {
    _checkUser();
    final normalized = normalizedCategoryActionName(name);
    final rows = await _categories
        .limit(501)
        .get(const GetOptions(source: Source.server));
    if (rows.docs.length > 500) {
      throw StateError('Too many categories to check safely in this version.');
    }
    if (rows.metadata.hasPendingWrites) {
      throw StateError(
        'Category changes are still syncing. Try again shortly.',
      );
    }
    _checkUser();
    final matches =
        rows.docs
            .map(ExpenseCategory.fromFirestore)
            .where(
              (category) =>
                  normalizedCategoryActionName(category.name) == normalized,
            )
            .toList()
          ..sort((a, b) => (a.archived ? 1 : 0).compareTo(b.archived ? 1 : 0));
    if (matches.isEmpty) return null;
    return CategoryActionResult(
      name: matches.first.name,
      archived: matches.first.archived,
    );
  }

  Future<CategoryActionResult> createConfirmed(
    CategoryActionPreview preview,
  ) async {
    _checkUser();
    if (preview.userId != userId ||
        preview.documentId != categoryActionDocumentId(preview.name)) {
      throw StateError('The category preview is invalid. Prepare it again.');
    }
    // Recheck legacy/random-ID categories at confirmation time as well.
    final existing = await findExisting(preview.name);
    if (existing != null) return existing;
    _checkUser();
    final reference = _categories.doc(preview.documentId);
    return _firestore.runTransaction<CategoryActionResult>((transaction) async {
      _checkUser();
      final document = await transaction.get(reference);
      if (document.exists) {
        final category = ExpenseCategory.fromFirestore(document);
        if (normalizedCategoryActionName(category.name) !=
            normalizedCategoryActionName(preview.name)) {
          throw StateError(
            'This category was renamed after an earlier request. '
            'Use Manage Categories; no record was overwritten.',
          );
        }
        return CategoryActionResult(
          name: category.name,
          archived: category.archived,
        );
      }
      _checkUser();
      transaction.set(reference, {
        'name': preview.name,
        'archived': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return CategoryActionResult(name: preview.name, created: true);
    });
  }
}
