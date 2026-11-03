import 'package:cloud_firestore/cloud_firestore.dart';

class SavingsContribution {
  final String id;
  final int amountMinor;
  final DateTime contributionDate;
  final String note;
  final DateTime? createdAt;

  const SavingsContribution({
    required this.id,
    required this.amountMinor,
    required this.contributionDate,
    this.note = '',
    this.createdAt,
  });

  factory SavingsContribution.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Contribution ${document.id} does not exist.');
    }

    return SavingsContribution(
      id: document.id,
      amountMinor: data['amountMinor'] as int,
      contributionDate: (data['contributionDate'] as Timestamp).toDate(),
      note: data['note'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'amountMinor': amountMinor,
      'contributionDate': Timestamp.fromDate(contributionDate),
      'note': note.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
