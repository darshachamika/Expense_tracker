import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/flow_doughnut_chart.dart';
import 'package:expense_tracker/widgets/ripple_advisor_visuals.dart';
import 'package:expense_tracker/widgets/flow_visuals.dart';
import 'package:expense_tracker/screens/profile_screen.dart';
import 'package:expense_tracker/theme/flow_theme.dart';
import 'package:expense_tracker/widgets/period_spending_overview.dart';
import 'package:expense_tracker/models/spending_period_summary.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/expense_category.dart';

Future<void> render(WidgetTester tester, Widget child, {ThemeData? theme}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  for (final allTime in [false, true]) {
    testWidgets(
      '${allTime ? 'All-time' : 'Year'} overview uses doughnuts with real totals',
      (tester) async {
        final expenses = [
          Expense(
            id: 'one',
            title: 'Lunch',
            amountMinor: 75000,
            categoryId: 'food',
            paymentMethod: 'cash',
            expenseDate: DateTime(2026, 10, 1),
          ),
          Expense(
            id: 'two',
            title: 'Bus',
            amountMinor: 25000,
            categoryId: 'transport',
            paymentMethod: 'cash',
            expenseDate: DateTime(2026, 11, 1),
          ),
        ];
        final summary = allTime
            ? SpendingPeriodSummary.allTime(
                expenses: expenses,
                now: DateTime(2026, 11, 8),
              )
            : SpendingPeriodSummary.forYear(
                expenses: expenses,
                year: 2026,
                now: DateTime(2026, 11, 8),
              );
        await render(
          tester,
          PeriodSpendingOverview(
            userId: 'test',
            summary: summary,
            onMonthSelected: (_) {},
            categoriesStream: Stream.value(const [
              ExpenseCategory(id: 'food', name: 'Food'),
              ExpenseCategory(id: 'transport', name: 'Transport'),
            ]),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BarChart), findsNothing);
        expect(find.byType(PieChart), findsNWidgets(2));
        final chart = tester.widgetList<PieChart>(find.byType(PieChart)).first;
        expect(
          chart.data.sections.fold<double>(0, (v, s) => v + s.value),
          100000,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty doughnut has a safe zero state', (tester) async {
    await render(tester, const FlowDoughnutChart(entries: []));
    await tester.pumpAndSettle();
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('No spending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('legend preserves percentages and monthly drilldown', (
    tester,
  ) async {
    var opened = false;
    await render(
      tester,
      FlowDoughnutChart(
        entries: [
          FlowDoughnutEntry('October', 75000, onOpen: () => opened = true),
          const FlowDoughnutEntry('November', 25000),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('75.0% of spending'), findsOneWidget);
    expect(find.text('25.0% of spending'), findsOneWidget);
    await tester.tap(find.text('October'));
    expect(opened, isTrue);
    expect(find.byType(BarChart), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Ripple bubble invokes the existing assistant entry point', (
    tester,
  ) async {
    var taps = 0;
    await render(tester, RippleBubbleButton(onPressed: () => taps++));
    await tester.tap(find.text('Ripple'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('answer is selectable and entrance settles in both themes', (
    tester,
  ) async {
    for (final theme in [FlowTheme.light, FlowTheme.dark]) {
      await render(
        tester,
        const RippleAnswerCard(
          question: 'My budget?',
          answer: 'You have Rs. 500 left.',
        ),
        theme: theme,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ripple’s explanation'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('Profile replaces More and cover has no edit control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const ProfileCover(cover: 0),
          bottomNavigationBar: FlowBottomNav(
            selectedIndex: 3,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('More'), findsNothing);
    expect(find.text('Change cover'), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
