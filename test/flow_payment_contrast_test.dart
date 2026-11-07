import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/theme/flow_theme.dart';
import 'package:expense_tracker/widgets/flow_home_view.dart';
import 'package:expense_tracker/widgets/google_sign_in_mark.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  for (final dark in [false, true]) {
    for (final method in ['cash', 'card', 'bank']) {
      testWidgets(
        '${dark ? 'dark' : 'light'} $method badge and category remain readable',
        (tester) async {
          final theme = dark ? FlowTheme.dark : FlowTheme.light;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Card(
                  child: FlowExpenseRow(
                    expense: Expense(
                      id: 'expense',
                      title: 'Lunch',
                      amountMinor: 50000,
                      categoryId: 'food',
                      paymentMethod: method,
                      expenseDate: DateTime(2026, 11, 7),
                    ),
                    categoryLabel: 'Food & Drink',
                  ),
                ),
              ),
            ),
          );
          final text = tester.widget<Text>(find.text(method));
          final badge = tester
              .widgetList<Container>(
                find.ancestor(
                  of: find.text(method),
                  matching: find.byType(Container),
                ),
              )
              .firstWhere((w) => w.decoration is BoxDecoration);
          final fill = (badge.decoration! as BoxDecoration).color!;
          expect(contrast(text.style!.color!, fill), greaterThanOrEqualTo(4.5));
          final category = tester.widget<Text>(find.text('Food & Drink'));
          expect(
            contrast(
              category.style!.color!,
              theme.cardTheme.color ?? theme.colorScheme.surface,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'Google mark is a bundled original image with no text substitute',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GoogleSignInMark())),
      );
      await tester.pumpAndSettle();
      final mark = tester.widget<Image>(find.byType(Image));
      expect(mark.image, isA<MemoryImage>());
      expect(mark.width, 20);
      expect(mark.height, 20);
      expect(find.text('G'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
