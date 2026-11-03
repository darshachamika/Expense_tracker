import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense.dart';
import '../models/planned_bill.dart';

class BillService {
  final String userId;
  final FirebaseFirestore _firestore;

  static const int maxAmountMinor = 99999999999;

  BillService({required this.userId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance {
    _validateId(userId);
  }

  CollectionReference<Map<String, dynamic>> get _bills {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('plannedBills');
  }

  CollectionReference<Map<String, dynamic>> get _expenses {
    return _firestore.collection('users').doc(userId).collection('expenses');
  }

  DocumentReference<Map<String, dynamic>> _billReference(String billId) {
    _validateId(billId);
    return _bills.doc(billId);
  }

  Stream<List<PlannedBill>> watchBills() {
    return _bills
        .orderBy('dueDate')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(PlannedBill.fromFirestore).toList(),
        );
  }

  Stream<PlannedBill?> watchBill(String billId) {
    return _billReference(billId).snapshots().map((document) {
      if (!document.exists) return null;

      return PlannedBill.fromFirestore(document);
    });
  }

  Future<String> createBill(PlannedBill bill) async {
    _validateBill(bill);

    final reference = _bills.doc();
    final data = bill.toCreateMap();

    // Each new bill starts its own recurrence series.
    data['seriesId'] = reference.id;

    await reference.set(data);

    return reference.id;
  }

  Future<void> updateBill(PlannedBill bill) async {
    _validateBill(bill);

    final reference = _billReference(bill.id);

    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(reference);

      if (!snapshot.exists) {
        throw StateError('This bill no longer exists.');
      }

      final current = PlannedBill.fromFirestore(snapshot);

      if (current.isPaid) {
        throw StateError('A paid bill cannot be edited.');
      }

      // Keeps the stored series ID and payment metadata unchanged.
      transaction.update(reference, bill.toUpdateMap());
    });
  }

  /// Returns the linked expense ID.
  ///
  /// Retrying payment for an already-paid bill returns its existing ID.
  Future<String> markAsPaid({
    required String billId,
    required DateTime paymentDate,
  }) async {
    final paidDate = _validatePaymentDate(paymentDate);
    final billReference = _billReference(billId);

    return _firestore.runTransaction<String>((transaction) async {
      final billSnapshot = await transaction.get(billReference);

      if (!billSnapshot.exists) {
        throw StateError('This bill no longer exists.');
      }

      final bill = PlannedBill.fromFirestore(billSnapshot);
      _validateBill(bill);

      if (bill.isPaid) {
        final existingExpenseId = bill.expenseId;

        if (existingExpenseId == null || existingExpenseId.isEmpty) {
          throw StateError('The paid bill has no linked expense.');
        }

        return existingExpenseId;
      }

      // A stable ID prevents duplicate payment expenses.
      final expenseReference = _expenses.doc('bill_${bill.id}');
      final expenseSnapshot = await transaction.get(expenseReference);

      if (expenseSnapshot.exists) {
        throw StateError(
          'A payment expense already exists for this unpaid bill.',
        );
      }

      DocumentReference<Map<String, dynamic>>? nextReference;
      Map<String, dynamic>? nextData;

      final nextDate = bill.nextDueDate;

      if (nextDate != null) {
        if (nextDate.year > 9999) {
          throw StateError('The next due date is outside the supported range.');
        }

        _validateId(bill.seriesId);

        final nextId = '${bill.seriesId}_${_dateKey(nextDate)}';
        final reference = _bills.doc(nextId);
        final nextSnapshot = await transaction.get(reference);

        if (nextSnapshot.exists) {
          throw StateError('The next bill occurrence already exists.');
        }

        nextReference = reference;
        nextData = bill.toCreateMap();
        nextData['dueDate'] = Timestamp.fromDate(nextDate);
      }

      final expense = Expense(
        id: expenseReference.id,
        title: bill.title,
        amountMinor: bill.amountMinor,
        categoryId: bill.categoryId,
        paymentMethod: bill.paymentMethod,
        note: bill.note,
        expenseDate: paidDate,
      );

      // All transaction reads finish before these writes.
      transaction.set(expenseReference, expense.toCreateMap());

      transaction.update(billReference, {
        'paidAt': FieldValue.serverTimestamp(),
        'expenseId': expenseReference.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (nextReference != null && nextData != null) {
        transaction.set(nextReference, nextData);
      }

      return expenseReference.id;
    });
  }

  DateTime _validatePaymentDate(DateTime value) {
    final local = value.toLocal();
    final date = DateTime(local.year, local.month, local.day);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (date.year < 2000 || date.isAfter(today)) {
      throw ArgumentError('Payment date must be between 2000 and today.');
    }

    return date;
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  void _validateBill(PlannedBill bill) {
    final title = bill.title.trim();

    if (title.isEmpty || title.length > 120) {
      throw ArgumentError('Bill title must contain 1–120 characters.');
    }

    if (bill.amountMinor <= 0 || bill.amountMinor > maxAmountMinor) {
      throw ArgumentError(
        'Enter a positive amount within the supported range.',
      );
    }

    _validateId(bill.categoryId);

    if (bill.categoryId.length > 100) {
      throw ArgumentError('Category ID is too long.');
    }

    if (!['cash', 'card', 'bank'].contains(bill.paymentMethod)) {
      throw ArgumentError('Choose a supported payment method.');
    }

    if (bill.note.trim().length > 2000) {
      throw ArgumentError('Note must be at most 2000 characters.');
    }

    final dueDate = bill.dueDate.toLocal();

    if (dueDate.year < 2000 || dueDate.year > 9999) {
      throw ArgumentError('Due year must be between 2000 and 9999.');
    }

    if (bill.recurrenceDay < 1 || bill.recurrenceDay > 31) {
      throw ArgumentError('Billing day must be between 1 and 31.');
    }
  }

  void _validateId(String id) {
    if (id.trim().isEmpty || id.contains('/')) {
      throw ArgumentError('A valid document ID is required.');
    }
  }
}
