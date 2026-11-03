import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyBudget {
  /// Firestore document ID, for example: 2026-11.
  final String id;

  /// Money stored in minor units: Rs. 1,000.00 = 100000.
  final int overallLimitMinor;

  /// Category ID -> budget in minor units.
  final Map<String, int> categoryLimitsMinor;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  MonthlyBudget({
    required this.id,
    required this.overallLimitMinor,
    Map<String, int> categoryLimitsMinor = const {},
    this.createdAt,
    this.updatedAt,
  }) : categoryLimitsMinor = Map.unmodifiable(categoryLimitsMinor);

  static String monthKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  factory MonthlyBudget.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Monthly budget ${document.id} does not exist.');
    }

    final categoryLimits = Map<String, int>.from(
      data['categoryLimitsMinor'] as Map,
    );

    return MonthlyBudget(
      id: document.id,
      overallLimitMinor: data['overallLimitMinor'] as int,
      categoryLimitsMinor: categoryLimits,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'overallLimitMinor': overallLimitMinor,
      'categoryLimitsMinor': Map<String, int>.from(categoryLimitsMinor),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toCreateMap() {
    return {...toUpdateMap(), 'createdAt': FieldValue.serverTimestamp()};
  }
}
