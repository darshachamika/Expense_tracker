import 'package:flutter_test/flutter_test.dart';

import '../lib/models/savings_goal.dart';

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
  });
}
