import 'package:flutter_test/flutter_test.dart';

import '../lib/controllers/gemini_advisor_controller.dart';
import '../lib/models/advisor_snapshot.dart';
import '../lib/models/budget_action.dart';

void main() {
  final now = DateTime(2026, 11, 6);

  test('parses rupees into cents and resolves the selected month', () {
    final current = BudgetActionInput.parse(
      'මේ මාසෙ Food budget එක Rs. 8,000.50 කරන්න',
      now: now,
    );
    expect(current.month, DateTime(2026, 11));
    expect(current.amountMinor, 800050);
    final future = BudgetActionInput.parse(
      'Set the overall budget for 2027-01 to LKR 12000',
      now: now,
    );
    expect(future.month, DateTime(2027, 1));
    expect(future.amountMinor, 1200000);
  });

  test('rejects ambiguous or invalid amounts and months', () {
    for (final request in [
      'Set Food budget to Rs. -8000',
      'Set Food budget to Rs. .50',
      'Set Food budget to Rs. 8,00',
      'Set Food budget to Rs. 8000.501',
      'Set Food budget to 8000 or 9000',
      'Set Food budget to USD 8000',
      'Set Food budget to 8 k',
      'Set Food budget to 0',
      'Set Food budget to 8000 for 2027-13',
    ]) {
      expect(
        () => BudgetActionInput.parse(request, now: now),
        throwsFormatException,
        reason: request,
      );
    }
  });

  test(
    'model can identify a literal category but cannot supply a write field',
    () {
      expect(
        BudgetActionTarget.parse(
          '{"scope":"category","category":"Food"}',
          'Set Food to 8000',
        )?.category,
        'Food',
      );
      expect(
        () => BudgetActionTarget.parse(
          '{"scope":"category","category":"Travel"}',
          'Set Food to 8000',
        ),
        throwsFormatException,
      );
      expect(
        () => BudgetActionTarget.parse(
          '{"scope":"overall","category":"","amountMinor":800000}',
          'Set overall to 8000',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'preview and cancel perform no save; stale confirmation removes preview',
    () async {
      var saves = 0;
      final controller = GeminiAdvisorController(
        userId: 'user',
        initialUserId: 'user',
        load: () async => AdvisorSnapshot.calculate(
          now: now,
          expenses: [],
          categories: [],
          bills: [],
          goals: [],
          savedByGoal: {},
        ),
        ask: ({required question, required snapshot}) async => '',
        planBudget: (instruction) async => BudgetActionTarget.parse(
          '{"scope":"category","category":"Food"}',
          instruction,
        ),
        buildBudgetPreview: (input, target) async => BudgetActionPreview(
          userId: 'user',
          month: input.month,
          previousMinor: 500000,
          proposedMinor: input.amountMinor,
          categoryId: 'food',
          categoryName: 'Food & Drinks',
        ),
        saveBudget: (preview) async {
          saves++;
          expect(preview.previousMinor, 500000);
          expect(preview.proposedMinor, 800000);
          throw const BudgetPreviewChanged();
        },
      );
      addTearDown(controller.dispose);
      controller.setMode(AdvisorMode.budget);
      controller.setDraft('Set Food budget for 2026-11 to Rs. 8,000');
      await controller.send();
      expect(controller.pendingBudget?.monthKey, '2026-11');
      expect(saves, 0);
      controller.cancelBudget();
      await controller.confirmBudget();
      expect(saves, 0);
      await controller.send();
      await controller.confirmBudget();
      expect(saves, 1);
      expect(controller.pendingBudget, isNull);
      expect(controller.error, contains('Preview the request again'));
    },
  );
}
