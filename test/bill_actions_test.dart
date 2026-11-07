import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/planned_bill.dart';
import 'package:expense_tracker/services/bill_service.dart';

// These doubles execute the real BillService transaction callbacks. Writes are
// staged until success, and a read after the first write fails the test.
// They do not emulate Firebase permissions or distributed transaction retries.
class _MemoryFirestore extends Fake implements FirebaseFirestore {
  final rows = <String, Map<String, dynamic>>{};
  var _tick = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final staged = {
      for (final entry in rows.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final stamp = Timestamp.fromDate(DateTime(2026, 1, 1, 0, 0, ++_tick));
    final result = await transactionHandler(_Transaction(staged, stamp));
    rows
      ..clear()
      ..addAll(staged);
    return result;
  }

  PlannedBill bill(String id) => PlannedBill.fromFirestore(
    _Snapshot<Map<String, dynamic>>(
      _Document('users/alice/plannedBills/$id'),
      rows['users/alice/plannedBills/$id'],
    ),
  );

  void seedBill({BillRecurrence recurrence = BillRecurrence.none}) {
    rows['users/alice/plannedBills/original'] = {
      'seriesId': 'original',
      'title': 'Water bill',
      'amountMinor': 50000,
      'categoryId': 'home',
      'paymentMethod': 'cash',
      'note': '',
      'dueDate': Timestamp.fromDate(DateTime(2026, 1, 31)),
      'recurrence': recurrence.name,
      'recurrenceDay': 31,
      'paidAt': null,
      'expenseId': null,
      'createdAt': Timestamp.fromDate(DateTime(2025, 12, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2025, 12, 1)),
      // Deliberately omit archived to exercise data created before this update.
    };
  }
}

// Firestore SDK interfaces are implemented here only as test doubles.
// ignore: subtype_of_sealed_class
class _Collection extends Fake implements CollectionReference<Map<String, dynamic>> {
  final String _path;
  _Collection(this._path);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document('$_path/${path ?? 'generated'}');
}

// Firestore SDK interfaces are implemented here only as test doubles.
// ignore: subtype_of_sealed_class
class _Document extends Fake implements DocumentReference<Map<String, dynamic>> {
  @override
  final String path;
  _Document(this.path);

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection('$path/$collectionPath');
}

// Firestore SDK interfaces are implemented here only as test doubles.
// ignore: subtype_of_sealed_class
class _Snapshot<T extends Object?> extends Fake implements DocumentSnapshot<T> {
  final DocumentReference<T> _reference;
  final T? _data;
  _Snapshot(this._reference, this._data);

  @override
  String get id => _reference.id;

  @override
  bool get exists => _data != null;

  @override
  T? data() => _data;
}

class _Transaction extends Fake implements Transaction {
  final Map<String, Map<String, dynamic>> _rows;
  final Timestamp _stamp;
  bool _hasWrites = false;
  _Transaction(this._rows, this._stamp);

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    if (_hasWrites) throw StateError('Transaction read after write.');
    final row = _rows[documentReference.path];
    final copy = row == null ? null : Map<String, dynamic>.from(row);
    return _Snapshot<T>(documentReference, copy as T?);
  }

  Map<String, dynamic> _resolved(Map<Object, Object?> values) => values.map(
    (key, value) => MapEntry(key as String, value is FieldValue ? _stamp : value),
  );

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    _hasWrites = true;
    _rows[documentReference.path] = _resolved(data as Map<String, dynamic>);
    return this;
  }

  @override
  Transaction update(DocumentReference<Object?> documentReference, Map<Object, Object?> data) {
    _hasWrites = true;
    final row = _rows[documentReference.path];
    if (row == null) throw StateError('Cannot update a missing document.');
    row.addAll(_resolved(data));
    return this;
  }

  @override
  Transaction delete(DocumentReference<Object?> documentReference) {
    _hasWrites = true;
    _rows.remove(documentReference.path);
    return this;
  }
}

void main() {
  const originalPath = 'users/alice/plannedBills/original';
  const expensePath = 'users/alice/expenses/bill_original';
  const nextPath = 'users/alice/plannedBills/original_2026-02-28';
  late _MemoryFirestore db;
  late BillService service;

  Future<void> pay() async {
    await service.markAsPaid(
      billId: 'original', paymentDate: DateTime.now(),
    );
  }

  setUp(() {
    db = _MemoryFirestore()..seedBill();
    service = BillService(userId: 'alice', firestore: db);
  });

  test('older documents default to unarchived', () {
    expect(db.bill('original').archived, isFalse);
  });

  test('undo removes the linked expense and returns the bill to pending', () async {
    await pay();
    final reviewed = db.bill('original');
    expect(db.rows.containsKey(expensePath), isTrue);
    expect(await service.undoPayment(reviewed), isTrue);
    expect(db.rows.containsKey(expensePath), isFalse);
    expect(db.bill('original').isPaid, isFalse);
    expect(db.bill('original').expenseId, isNull);
    expect(await service.undoPayment(reviewed), isFalse);
  });

  test('undo then repayment records one expense with the stable ID', () async {
    await pay();
    await service.undoPayment(db.bill('original'));
    await pay();
    await pay();
    expect(db.rows.keys.where((path) => path.contains('/expenses/')), hasLength(1));
    expect(db.bill('original').expenseId, 'bill_original');
  });

  test('archive and restore retain the expense and payment timestamp', () async {
    await pay();
    final paid = db.bill('original');
    final expense = Map<String, dynamic>.from(db.rows[expensePath]!);
    await service.setArchived(paid, archived: true);
    expect(db.bill('original').archived, isTrue);
    expect(db.bill('original').paidAt, paid.paidAt);
    expect(db.rows[expensePath], expense);
    expect(await service.setArchived(paid, archived: true), isFalse);
    await pay();
    expect(db.rows[expensePath], expense);
    await service.setArchived(db.bill('original'), archived: false);
    expect(db.bill('original').archived, isFalse);
    expect(db.rows[expensePath], expense);
  });

  test('pending bills can be deleted and repeated deletion is harmless', () async {
    final reviewed = db.bill('original');
    expect(await service.deleteBill(reviewed), isTrue);
    expect(db.rows.containsKey(originalPath), isFalse);
    expect(await service.deleteBill(reviewed), isFalse);
    expect(db.rows.containsKey(expensePath), isFalse);
  });

  test('a stale pending confirmation cannot delete a newly paid bill', () async {
    final reviewed = db.bill('original');
    await pay();
    await expectLater(service.deleteBill(reviewed), throwsStateError);
    expect(db.bill('original').isPaid, isTrue);
    expect(db.rows.containsKey(expensePath), isTrue);
  });

  test('pending bills cannot be archived', () async {
    await expectLater(service.setArchived(db.bill('original'), archived: true), throwsStateError);
    expect(db.bill('original').archived, isFalse);
  });

  test('archived paid bill requires restore before undo', () async {
    await pay();
    await service.setArchived(db.bill('original'), archived: true);
    await expectLater(service.undoPayment(db.bill('original')), throwsStateError);
    expect(db.rows.containsKey(expensePath), isTrue);
    await service.setArchived(db.bill('original'), archived: false);
    await service.undoPayment(db.bill('original'));
    expect(db.bill('original').isPaid, isFalse);
  });

  test('a stale undo cannot reverse a later repayment', () async {
    await pay();
    final firstPayment = db.bill('original');
    await service.undoPayment(firstPayment);
    await pay();
    await expectLater(service.undoPayment(firstPayment), throwsStateError);
    expect(db.bill('original').isPaid, isTrue);
    expect(db.rows.containsKey(expensePath), isTrue);
  });

  test('changed expense aborts undo with both records retained', () async {
    await pay();
    db.rows[expensePath]!['amountMinor'] = 60000;
    await expectLater(service.undoPayment(db.bill('original')), throwsStateError);
    expect(db.bill('original').isPaid, isTrue);
    expect(db.rows[expensePath]!['amountMinor'], 60000);
  });

  test('stale deletion cannot remove an edited pending bill', () async {
    final reviewed = db.bill('original');
    db.rows[originalPath]!['title'] = 'Updated bill';
    await expectLater(service.deleteBill(reviewed), throwsStateError);
    expect(db.bill('original').title, 'Updated bill');
  });

  test('monthly undo removes the untouched next occurrence and can be repaid', () async {
    db.seedBill(recurrence: BillRecurrence.monthly);
    await pay();
    expect(db.rows.containsKey(nextPath), isTrue);
    await service.undoPayment(db.bill('original'));
    expect(db.rows.containsKey(nextPath), isFalse);
    expect(db.rows.containsKey(expensePath), isFalse);
    await pay();
    expect(db.rows.containsKey(nextPath), isTrue);
    expect(db.rows.containsKey(expensePath), isTrue);
  });

  test('monthly undo stops if the next occurrence was edited', () async {
    db.seedBill(recurrence: BillRecurrence.monthly);
    await pay();
    db.rows[nextPath]!['amountMinor'] = 60000;
    await expectLater(service.undoPayment(db.bill('original')), throwsStateError);
    expect(db.rows.containsKey(nextPath), isTrue);
    expect(db.rows.containsKey(expensePath), isTrue);
    expect(db.bill('original').isPaid, isTrue);
  });

  test('monthly undo stops if the next occurrence was paid', () async {
    db.seedBill(recurrence: BillRecurrence.monthly);
    await pay();
    await service.markAsPaid(billId: 'original_2026-02-28', paymentDate: DateTime.now());
    await expectLater(service.undoPayment(db.bill('original')), throwsStateError);
    expect(db.rows.containsKey(nextPath), isTrue);
    expect(db.rows.containsKey(expensePath), isTrue);
    expect(db.bill('original').isPaid, isTrue);
  });

  test('monthly undo tolerates a next pending occurrence already deleted', () async {
    db.seedBill(recurrence: BillRecurrence.monthly);
    await pay();
    await service.deleteBill(db.bill('original_2026-02-28'));
    await service.undoPayment(db.bill('original'));
    expect(db.rows.containsKey(nextPath), isFalse);
    expect(db.rows.containsKey(expensePath), isFalse);
    expect(db.bill('original').isPaid, isFalse);
  });
}
