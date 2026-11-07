import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/expense_category.dart';
import 'package:expense_tracker/models/monthly_budget.dart';
import 'package:expense_tracker/theme/flow_theme.dart';
import 'package:expense_tracker/widgets/flow_format.dart';
import 'package:expense_tracker/widgets/flow_home_view.dart';
import 'package:expense_tracker/widgets/flow_activity_view.dart';

Expense expense(String id, int minor, DateTime date, {String category = 'food'}) => Expense(id: id, title: id, amountMinor: minor, categoryId: category, paymentMethod: 'Cash', expenseDate: date);
Widget surface(Widget child, {double scale = 1}) => MaterialApp(theme: FlowTheme.light, home: Builder(builder: (context) => MediaQuery(
  data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)), child: Scaffold(body: child),
)));

void main() {
  test('weekly bars use exact days across a month boundary without changing monthly spending', () {
    final expenses = [expense('October', 10000, DateTime(2026, 10, 31)), expense('November', 65000, DateTime(2026, 11, 1)), expense('Older', 90000, DateTime(2026, 10, 20))];
    final week = flowWeek(expenses, DateTime(2026, 11), DateTime(2026, 11, 2));
    expect(week.length, 7);
    expect(week.first.date, DateTime(2026, 10, 27));
    expect(week.last.date, DateTime(2026, 11, 2));
    expect(week.fold<int>(0, (sum, value) => sum + value.amountMinor), 75000);
  });
  test('past-month chart ends at the selected month end, including leap day', () {
    final week = flowWeek([expense('Leap day', 500, DateTime(2024, 2, 29)), expense('March', 900, DateTime(2024, 3, 1))], DateTime(2024, 2), DateTime(2026, 11, 7));
    expect(week.last.date, DateTime(2024, 2, 29));
    expect(week.last.amountMinor, 500);
    expect(week.fold<int>(0, (sum, value) => sum + value.amountMinor), 500);
  });
  test('money keeps cents and signs while adding thousands separators', () {
    expect(FlowFormat.money(4285000), 'Rs. 42,850');
    expect(FlowFormat.money(-123456), '-Rs. 1,234.56');
    expect(FlowFormat.money(0), 'Rs. 0');
    expect(FlowFormat.greeting(DateTime(2026, 11, 7, 9)), 'Good morning');
    expect(FlowFormat.greeting(DateTime(2026, 11, 7, 14)), 'Good afternoon');
    expect(FlowFormat.greeting(DateTime(2026, 11, 7, 19)), 'Good evening');
  });

  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('Home shows greeting, real totals, compact tiles and bars at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(surface(FlowHomeView(
        expenses: [expense('Lunch', 65000, DateTime(2026, 11, 7)), expense('Bus', 18000, DateTime(2026, 11, 7)), expense('Old', 90000, DateTime(2026, 10, 7))],
        month: DateTime(2026, 11), now: DateTime(2026, 11, 7, 9), displayName: 'Chami',
        budget: MonthlyBudget(id: '2026-11', overallLimitMinor: 100000),
        categoryLabel: (_) => 'Food', onMonth: (_) {}, onActivity: () {}, onAnalytics: () {},
      ), scale: width == 320 ? 1.5 : 1));
      await tester.pumpAndSettle();
      expect(find.text('Good morning, Chami'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('flow-home-total'))).data, 'Rs. 830');
      expect(find.text('Monthly budget'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Weekly spending'), 120);
      expect(find.byType(FlowWeekChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Activity groups real transactions, computes totals and preserves edit action', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    String? edited;
    await tester.pumpWidget(surface(FlowActivityView(
      expenses: [expense('Lunch', 65000, DateTime(2026, 11, 7)), expense('Bus', 18000, DateTime(2026, 11, 7)), expense('Groceries', 320000, DateTime(2026, 11, 6))],
      categories: const [ExpenseCategory(id: 'food', name: 'Food', archived: false)],
      periodLabel: 'November spending', dateFilterLabel: 'This month', searchController: controller,
      onSearch: (_) {}, onCategory: (_) {}, onFilters: () {}, onClear: () {},
      onEdit: (value) => edited = value.id, onDelete: (_) {}, categoryLabel: (_) => 'Food', now: DateTime(2026, 11, 7),
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('flow-activity-total'))).data, 'Rs. 4,030');
    expect(find.text('Today, Nov 7, 2026'), findsOneWidget);
    expect(find.text('Yesterday, Nov 6, 2026'), findsOneWidget);
    expect(find.text('Total: Rs. 830'), findsOneWidget);
    await tester.tap(find.text('Lunch'));
    expect(edited, 'Lunch');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
