import 'package:cloud_firestore/cloud_firestore.dart';

class SavingsGoal {
  final String id;
  final String title;
  final int targetMinor;
  final DateTime? targetDate;
  final bool archived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SavingsGoal({
    required this.id,
    required this.title,
    required this.targetMinor,
    this.targetDate,
    this.archived = false,
    this.createdAt,
    this.updatedAt,
  });

  int remainingMinor(int savedMinor) {
    final remaining = targetMinor - savedMinor;
    return remaining > 0 ? remaining : 0;
  }

  bool isCompleted(int savedMinor) => savedMinor >= targetMinor;

  /// Display progress is capped at 100%.
  double progress(int savedMinor) {
    if (targetMinor <= 0) return 0;

    return (savedMinor / targetMinor).clamp(0.0, 1.0).toDouble();
  }

  /// Includes the current calendar month as a saving opportunity.
  ///
  /// Returns:
  /// - 0 when the goal is completed.
  /// - null when there is no deadline or the deadline has passed.
  /// - Otherwise, the monthly amount rounded UP to a minor unit.
  int? monthlyRequiredMinor({required int savedMinor, DateTime? now}) {
    final remaining = remainingMinor(savedMinor);
    if (remaining == 0) return 0;

    final deadline = targetDate?.toLocal();
    if (deadline == null) return null;

    final current = (now ?? DateTime.now()).toLocal();
    final today = DateTime(current.year, current.month, current.day);
    final dueDate = DateTime(deadline.year, deadline.month, deadline.day);

    if (dueDate.isBefore(today)) return null;

    final months =
        (dueDate.year - today.year) * 12 + dueDate.month - today.month + 1;

    return (remaining + months - 1) ~/ months;
  }

  factory SavingsGoal.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Savings goal ${document.id} does not exist.');
    }

    return SavingsGoal(
      id: document.id,
      title: data['title'] as String,
      targetMinor: data['targetMinor'] as int,
      targetDate: (data['targetDate'] as Timestamp?)?.toDate(),
      archived: data['archived'] as bool,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title.trim(),
      'targetMinor': targetMinor,
      'targetDate': targetDate == null ? null : Timestamp.fromDate(targetDate!),
      'archived': archived,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toCreateMap() {
    return {...toUpdateMap(), 'createdAt': FieldValue.serverTimestamp()};
  }
}
