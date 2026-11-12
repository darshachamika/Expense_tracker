import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/savings_goal.dart';

void main() {
  test('remaining amount and progress handle overfunding', () {
    const goal = SavingsGoal(
      id: 'laptop',
      title: 'Laptop',
      targetMinor: 100000,
    );

    expect(goal.remainingMinor(25000), 75000);
    expect(goal.progress(25000), 0.25);
    expect(goal.isCompleted(25000), isFalse);

    expect(goal.remainingMinor(120000), 0);
    expect(goal.progress(120000), 1.0);
    expect(goal.isCompleted(120000), isTrue);
  });

  test('monthly saving includes current month and rounds up', () {
    final goal = SavingsGoal(
      id: 'trip',
      title: 'Trip',
      targetMinor: 10000,
      targetDate: DateTime(2026, 12, 31),
    );

    // October, November and December: three saving opportunities.
    expect(
      goal.monthlyRequiredMinor(savedMinor: 0, now: DateTime(2026, 10, 15)),
      3334,
    );
  });

  test('deadline today requires the full remaining amount', () {
    final goal = SavingsGoal(
      id: 'fund',
      title: 'Fund',
      targetMinor: 10000,
      targetDate: DateTime(2026, 11, 3),
    );

    expect(
      goal.monthlyRequiredMinor(
        savedMinor: 2500,
        now: DateTime(2026, 11, 3, 18),
      ),
      7500,
    );
  });

  test('monthly plan changes at month rollover and after a contribution', () {
    final goal = SavingsGoal(
      id: 'laptop',
      title: 'Laptop',
      targetMinor: 12000000,
      targetDate: DateTime(2027, 4, 30),
    );

    final november = DateTime(2026, 11, 30);
    final december = DateTime(2026, 12, 1);

    expect(goal.savingMonthsLeft(now: november), 6);
    expect(goal.savingMonthsLeft(now: december), 5);
    expect(
      goal.monthlyRequiredMinor(savedMinor: 3000000, now: november),
      1500000,
    );
    expect(
      goal.monthlyRequiredMinor(savedMinor: 3000000, now: december),
      1800000,
    );
    expect(
      goal.monthlyRequiredMinor(savedMinor: 5000000, now: december),
      1400000,
    );
  });

  test(
    'next 12 months uses the monthly pace and caps at the remaining amount',
    () {
      final goal = SavingsGoal(
        id: 'fund',
        title: 'Fund',
        targetMinor: 240001,
        targetDate: DateTime(2028, 10, 31),
      );

      expect(
        goal.nextTwelveMonthsRequiredMinor(
          savedMinor: 0,
          now: DateTime(2026, 11, 1),
        ),
        120012,
      );
      expect(
        goal.nextTwelveMonthsRequiredMinor(
          savedMinor: 240000,
          now: DateTime(2026, 11, 1),
        ),
        1,
      );
    },
  );

  test('missing or overdue deadlines have no monthly estimate', () {
    const noDeadline = SavingsGoal(
      id: 'emergency',
      title: 'Emergency fund',
      targetMinor: 10000,
    );

    final overdue = SavingsGoal(
      id: 'trip',
      title: 'Trip',
      targetMinor: 10000,
      targetDate: DateTime(2026, 10, 31),
    );

    final now = DateTime(2026, 11, 3);

    expect(noDeadline.monthlyRequiredMinor(savedMinor: 0, now: now), isNull);

    expect(overdue.monthlyRequiredMinor(savedMinor: 0, now: now), isNull);

    expect(overdue.monthlyRequiredMinor(savedMinor: 10000, now: now), 0);
    expect(
      noDeadline.nextTwelveMonthsRequiredMinor(savedMinor: 0, now: now),
      isNull,
    );
    expect(
      overdue.nextTwelveMonthsRequiredMinor(savedMinor: 0, now: now),
      isNull,
    );
    expect(
      overdue.nextTwelveMonthsRequiredMinor(savedMinor: 10000, now: now),
      0,
    );
  });
}
