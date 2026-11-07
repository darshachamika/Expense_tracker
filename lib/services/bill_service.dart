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

      if (current.isPaid || current.archived) {
        throw StateError('A paid or archived bill cannot be edited.');
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

      if (bill.archived) {
        throw StateError('Restore this bill before recording a payment.');
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

  /// Archives one paid occurrence. Its expense remains recorded.
  Future<bool> setArchived(PlannedBill reviewed, {required bool archived}) async {
    final reference = _billReference(reviewed.id);
    return _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw StateError('This bill no longer exists.');
      final current = PlannedBill.fromFirestore(snapshot);
      if (!current.isPaid) {
        throw StateError('Only paid bills can be archived.');
      }
      if (current.archived == archived) return false;
      _checkReviewedBill(current, reviewed);
      transaction.update(reference, {
        'archived': archived,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  /// Deletes one unpaid occurrence after checking the reviewed state.
  Future<bool> deleteBill(PlannedBill reviewed) async {
    final reference = _billReference(reviewed.id);
    return _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) return false;
      final current = PlannedBill.fromFirestore(snapshot);
      if (current.isPaid || current.archived) {
        throw StateError('Use Undo payment or Archive for a paid bill.');
      }
      _checkReviewedBill(current, reviewed);
      if (current.expenseId != null) {
        throw StateError('This bill still has a payment link. Refresh its status before deleting.');
      }
      final expense = await transaction.get(_expenses.doc('bill_${current.id}'));
      if (expense.exists) {
        throw StateError('This bill has a payment expense. Refresh its status before deleting.');
      }
      transaction.delete(reference);
      return true;
    });
  }

  /// Reverses the reviewed payment and removes its linked expense atomically.
  /// For monthly bills, only an untouched unpaid next occurrence is removed.
  Future<bool> undoPayment(PlannedBill reviewed) async {
    final reference = _billReference(reviewed.id);
    return _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw StateError('This bill no longer exists.');
      final current = PlannedBill.fromFirestore(snapshot);
      if (!current.isPaid) return false;
      if (current.archived) {
        throw StateError('Restore this bill before undoing its payment.');
      }
      _checkReviewedBill(current, reviewed);
      final expenseId = current.expenseId;
      if (expenseId != 'bill_${current.id}') {
        throw StateError('The payment link could not be verified. Refresh the bill.');
      }
      final expenseReference = _expenses.doc(expenseId);
      final expenseSnapshot = await transaction.get(expenseReference);
      if (!expenseSnapshot.exists) {
        throw StateError('The linked expense is missing. Check this bill before reversing it.');
      }
      final expense = Expense.fromFirestore(expenseSnapshot);
      if (expense.title != current.title.trim() ||
          expense.amountMinor != current.amountMinor ||
          expense.categoryId != current.categoryId ||
          expense.paymentMethod != current.paymentMethod ||
          expense.note != current.note.trim()) {
        throw StateError('The linked expense changed. Check this payment before reversing it.');
      }

      DocumentReference<Map<String, dynamic>>? nextReference;
      final nextDate = current.nextDueDate;
      if (nextDate != null) {
        _validateId(current.seriesId);
        final candidate = _bills.doc('${current.seriesId}_${_dateKey(nextDate)}');
        final nextSnapshot = await transaction.get(candidate);
        if (nextSnapshot.exists) {
          final next = PlannedBill.fromFirestore(nextSnapshot);
          if (next.isPaid || next.archived ||
              next.expenseId != null ||
              next.createdAt == null || next.updatedAt != next.createdAt ||
              next.seriesId != current.seriesId ||
              next.title != current.title ||
              next.amountMinor != current.amountMinor ||
              next.categoryId != current.categoryId ||
              next.paymentMethod != current.paymentMethod ||
              next.note != current.note ||
              next.dueDate != nextDate ||
              next.recurrence != current.recurrence ||
              next.recurrenceDay != current.recurrenceDay) {
            throw StateError(
              'The next monthly bill has changed or been paid. '
              'Undo is available only while that occurrence is untouched and unpaid.',
            );
          }
          // Check the stable payment ID too, including inconsistent legacy data.
          final nextExpense = await transaction.get(_expenses.doc('bill_${next.id}'));
          if (nextExpense.exists) {
            throw StateError('The next monthly bill has a payment expense. Check it before undoing.');
          }
          nextReference = candidate;
        }
      }

      // All reads are complete before deleting the expense and resetting status.
      transaction.delete(expenseReference);
      if (nextReference != null) transaction.delete(nextReference);
      transaction.update(reference, {
        'paidAt': null,
        'expenseId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  void _checkReviewedBill(PlannedBill current, PlannedBill reviewed) {
    if (current.seriesId != reviewed.seriesId ||
        current.title != reviewed.title ||
        current.amountMinor != reviewed.amountMinor ||
        current.categoryId != reviewed.categoryId ||
        current.paymentMethod != reviewed.paymentMethod ||
        current.note != reviewed.note ||
        current.dueDate != reviewed.dueDate ||
        current.recurrence != reviewed.recurrence ||
        current.recurrenceDay != reviewed.recurrenceDay ||
        current.paidAt != reviewed.paidAt ||
        current.expenseId != reviewed.expenseId ||
        current.archived != reviewed.archived ||
        current.updatedAt != reviewed.updatedAt) {
      throw StateError('This bill changed after you reviewed it. Refresh and try again.');
    }
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
