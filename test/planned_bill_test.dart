import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/planned_bill.dart';

PlannedBill bill({
  required DateTime dueDate,
  BillRecurrence recurrence = BillRecurrence.none,
  int? recurrenceDay,
  DateTime? paidAt,
}) {
  return PlannedBill(
    id: 'bill-1',
    seriesId: 'series-1',
    title: 'Internet',
    amountMinor: 500000,
    categoryId: 'home',
    paymentMethod: 'bank',
    dueDate: dueDate,
    recurrence: recurrence,
    recurrenceDay: recurrenceDay ?? dueDate.day,
    paidAt: paidAt,
    expenseId: paidAt == null ? null : 'expense-1',
  );
}

void main() {
  test('a bill due today is upcoming, not overdue', () {
    final planned = bill(dueDate: DateTime(2026, 11, 3));

    expect(
      planned.status(now: DateTime(2026, 11, 3, 23)),
      PlannedBillStatus.upcoming,
    );

    expect(
      planned.status(now: DateTime(2026, 11, 4)),
      PlannedBillStatus.overdue,
    );
  });

  test('paid status takes priority over the due date', () {
    final planned = bill(
      dueDate: DateTime(2026, 10, 1),
      paidAt: DateTime(2026, 10, 2),
    );

    expect(planned.status(now: DateTime(2026, 11, 3)), PlannedBillStatus.paid);
  });

  test('monthly recurrence preserves day 31 through February', () {
    final january = bill(
      dueDate: DateTime(2026, 1, 31),
      recurrence: BillRecurrence.monthly,
    );

    expect(january.nextDueDate, DateTime(2026, 2, 28));

    final february = bill(
      dueDate: january.nextDueDate!,
      recurrence: BillRecurrence.monthly,
      recurrenceDay: january.recurrenceDay,
    );

    expect(february.nextDueDate, DateTime(2026, 3, 31));
  });

  test('recurrence handles leap years and year boundaries', () {
    expect(
      bill(
        dueDate: DateTime(2024, 1, 31),
        recurrence: BillRecurrence.monthly,
      ).nextDueDate,
      DateTime(2024, 2, 29),
    );

    expect(
      bill(
        dueDate: DateTime(2026, 12, 15),
        recurrence: BillRecurrence.monthly,
      ).nextDueDate,
      DateTime(2027, 1, 15),
    );
  });

  test('a one-time bill has no next occurrence', () {
    expect(bill(dueDate: DateTime(2026, 11, 3)).nextDueDate, isNull);
  });
}
