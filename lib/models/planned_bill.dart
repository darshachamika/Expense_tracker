import 'package:cloud_firestore/cloud_firestore.dart';

enum BillRecurrence { none, monthly }

enum PlannedBillStatus { upcoming, overdue, paid }

class PlannedBill {
  final String id;

  /// Shared by all occurrences of the same recurring bill.
  final String seriesId;

  final String title;
  final int amountMinor;
  final String categoryId;
  final String paymentMethod;
  final String note;
  final DateTime dueDate;
  final BillRecurrence recurrence;

  /// Original billing day, preserved across shorter months.
  /// Example: 31 -> February 28 -> March 31.
  final int recurrenceDay;

  final bool archived;
  final DateTime? paidAt;
  final String? expenseId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PlannedBill({
    required this.id,
    required this.seriesId,
    required this.title,
    required this.amountMinor,
    required this.categoryId,
    required this.paymentMethod,
    required this.dueDate,
    required this.recurrenceDay,
    this.recurrence = BillRecurrence.none,
    this.note = '',
    this.archived = false,
    this.paidAt,
    this.expenseId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPaid => paidAt != null;

  PlannedBillStatus status({DateTime? now}) {
    if (isPaid) return PlannedBillStatus.paid;

    final current = (now ?? DateTime.now()).toLocal();
    final today = DateTime(current.year, current.month, current.day);

    final localDue = dueDate.toLocal();
    final dueDay = DateTime(localDue.year, localDue.month, localDue.day);

    return dueDay.isBefore(today)
        ? PlannedBillStatus.overdue
        : PlannedBillStatus.upcoming;
  }

  DateTime? get nextDueDate {
    if (recurrence == BillRecurrence.none) return null;

    if (recurrenceDay < 1 || recurrenceDay > 31) {
      throw StateError('Billing day must be between 1 and 31.');
    }

    final localDue = dueDate.toLocal();
    final nextMonth = DateTime(localDue.year, localDue.month + 1);

    final daysInNextMonth = DateTime(
      nextMonth.year,
      nextMonth.month + 1,
      0,
    ).day;

    final day = recurrenceDay > daysInNextMonth
        ? daysInNextMonth
        : recurrenceDay;

    return DateTime(nextMonth.year, nextMonth.month, day);
  }

  factory PlannedBill.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Planned bill ${document.id} does not exist.');
    }

    return PlannedBill(
      id: document.id,
      seriesId: data['seriesId'] as String,
      title: data['title'] as String,
      amountMinor: data['amountMinor'] as int,
      categoryId: data['categoryId'] as String,
      paymentMethod: data['paymentMethod'] as String,
      note: data['note'] as String,
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      recurrence: BillRecurrence.values.byName(data['recurrence'] as String),
      recurrenceDay: data['recurrenceDay'] as int,
      archived: data['archived'] as bool? ?? false,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      expenseId: data['expenseId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Editable details only.
  /// Payment metadata is handled separately by the payment transaction.
  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title.trim(),
      'amountMinor': amountMinor,
      'categoryId': categoryId,
      'paymentMethod': paymentMethod,
      'note': note.trim(),
      'dueDate': Timestamp.fromDate(dueDate),
      'recurrence': recurrence.name,
      'recurrenceDay': recurrenceDay,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toCreateMap() {
    return {
      ...toUpdateMap(),
      'seriesId': seriesId,
      'archived': false,
      'paidAt': null,
      'expenseId': null,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
