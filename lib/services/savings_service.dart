import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/savings_contribution.dart';
import '../models/savings_goal.dart';

class SavingsService {
  final String userId;
  final FirebaseFirestore _firestore;

  static const int maxAmountMinor = 99999999999;

  SavingsService({required this.userId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance {
    _validateId(userId);
  }

  CollectionReference<Map<String, dynamic>> get _goals {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('savingsGoals');
  }

  DocumentReference<Map<String, dynamic>> _goal(String goalId) {
    _validateId(goalId);
    return _goals.doc(goalId);
  }

  CollectionReference<Map<String, dynamic>> _contributions(String goalId) {
    return _goal(goalId).collection('contributions');
  }

  Stream<List<SavingsGoal>> watchGoals() {
    return _goals
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(SavingsGoal.fromFirestore).toList(),
        );
  }

  Stream<List<SavingsContribution>> watchContributions(String goalId) {
    return _contributions(goalId)
        .orderBy('contributionDate', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(SavingsContribution.fromFirestore).toList(),
        );
  }

  Future<String> createGoal(SavingsGoal goal) async {
    _validateGoal(goal);

    final data = goal.toCreateMap();
    data['archived'] = false;

    final document = await _goals.add(data);
    return document.id;
  }

  Future<void> updateGoal(SavingsGoal goal) async {
    _validateGoal(goal);

    // Editing goal details must not overwrite its archive state.
    final data = goal.toUpdateMap();
    data.remove('archived');

    await _goal(goal.id).update(data);
  }

  Future<void> setArchived(String goalId, bool archived) async {
    await _goal(
      goalId,
    ).update({'archived': archived, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<String> addContribution({
    required String goalId,
    required int amountMinor,
    required DateTime contributionDate,
    String note = '',
  }) async {
    _validateAmount(amountMinor);

    final cleanNote = note.trim();

    if (cleanNote.length > 500) {
      throw ArgumentError('Note must be at most 500 characters.');
    }

    final localDate = contributionDate.toLocal();
    final date = DateTime(localDate.year, localDate.month, localDate.day);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (date.year < 2000 || date.isAfter(today)) {
      throw ArgumentError('Contribution date must be between 2000 and today.');
    }

    final goalReference = _goal(goalId);
    final contributionReference = _contributions(goalId).doc();

    final contribution = SavingsContribution(
      id: contributionReference.id,
      amountMinor: amountMinor,
      contributionDate: date,
      note: cleanNote,
    );

    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(goalReference);

      if (!snapshot.exists) {
        throw StateError('This savings goal no longer exists.');
      }

      final goal = SavingsGoal.fromFirestore(snapshot);

      if (goal.archived) {
        throw StateError('Restore this goal before adding contributions.');
      }

      transaction.set(contributionReference, contribution.toCreateMap());
    });

    return contributionReference.id;
  }

  Future<void> removeContribution({
    required String goalId,
    required String contributionId,
  }) async {
    _validateId(contributionId);

    await _contributions(goalId).doc(contributionId).delete();
  }

  void _validateGoal(SavingsGoal goal) {
    final title = goal.title.trim();

    if (title.isEmpty || title.length > 120) {
      throw ArgumentError('Goal title must contain 1–120 characters.');
    }

    _validateAmount(goal.targetMinor);

    final targetDate = goal.targetDate?.toLocal();

    if (targetDate != null &&
        (targetDate.year < 2000 || targetDate.year > 9999)) {
      throw ArgumentError('Target year must be between 2000 and 9999.');
    }
  }

  void _validateAmount(int amountMinor) {
    if (amountMinor <= 0 || amountMinor > maxAmountMinor) {
      throw ArgumentError(
        'Enter a positive amount within the supported range.',
      );
    }
  }

  void _validateId(String id) {
    if (id.trim().isEmpty || id.contains('/')) {
      throw ArgumentError('A valid document ID is required.');
    }
  }
}
