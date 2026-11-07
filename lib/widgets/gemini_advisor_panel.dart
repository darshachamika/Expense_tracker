import 'dart:async';

import 'package:flutter/material.dart';

import 'ripple_advisor_visuals.dart';

import '../controllers/gemini_advisor_controller.dart';
import '../models/advisor_snapshot.dart';

/// The same content is used in both the compact sheet and the full page.
class GeminiAdvisorPanel extends StatefulWidget {
  final GeminiAdvisorController controller;
  final ScrollController? scrollController;
  final VoidCallback? onExpand;
  final VoidCallback? onClose;
  final bool compact;

  const GeminiAdvisorPanel({
    super.key,
    required this.controller,
    this.scrollController,
    this.onExpand,
    this.onClose,
    this.compact = false,
  });

  @override
  State<GeminiAdvisorPanel> createState() => _GeminiAdvisorPanelState();
}

class _GeminiAdvisorPanelState extends State<GeminiAdvisorPanel> {
  late final TextEditingController _question;

  void _syncDraft() {
    final draft = widget.controller.draft;
    if (_question.text != draft) {
      _question.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _question = TextEditingController(text: widget.controller.draft);
    widget.controller.addListener(_syncDraft);
    // Do not notify listeners synchronously while an ancestor is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.ensureLoaded());
    });
  }

  @override
  void didUpdateWidget(covariant GeminiAdvisorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncDraft);
      widget.controller.addListener(_syncDraft);
      _syncDraft();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncDraft);
    _question.dispose();
    super.dispose();
  }

  Widget _amountRow(String label, int? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value == null ? 'Not set' : advisorMoney(value),
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: value != null && value < 0
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _facts(AdvisorSnapshot snapshot) => ExpansionTile(
    key: PageStorageKey('advisor-facts-${widget.compact}'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    title: const Text(
      'Recorded data',
      style: TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${snapshot.capturedAt.year}-'
      '${snapshot.capturedAt.month.toString().padLeft(2, '0')} · '
      '${advisorMoney(snapshot.summary.totalMinor)} spent',
    ),
    children: [
      _amountRow('Recorded spending', snapshot.summary.totalMinor),
      _amountRow('Monthly budget', snapshot.budget?.overallLimitMinor),
      _amountRow('Budget remaining', snapshot.remainingMinor),
      _amountRow('Unpaid bills due by month-end', snapshot.pendingBillsMinor),
      _amountRow('Overdue bills included above', snapshot.overdueBillsMinor),
      _amountRow(
        'Budget remaining after bills',
        snapshot.remainingAfterBillsMinor,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Active goals: ${snapshot.activeGoalCount}\n'
          'Read started: ${snapshot.capturedAt.toString().split('.').first}\n'
          'Budget estimate, not a bank balance. Only recorded bill occurrences '
          'are reserved. Savings contributions are separate from spending.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final advice = controller.mode == AdvisorMode.advice;
        final budget = controller.pendingBudget;
        final expense = controller.pendingExpense;
        final disabled = controller.busy || !controller.sessionValid;
        final requestDisabled = disabled || controller.expenseRetryRequired;
        return Column(
          children: [
            if (widget.compact) ...[
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 8, top: 4),
                child: Row(
                  children: [
                    const RippleMark(size: 30),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Ripple',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Expand advisor',
                      onPressed: widget.onExpand,
                      icon: const Icon(Icons.open_in_full, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Close advisor',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  Text(
                    'Your spending, explained.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'English or Sinhala · Review changes before saving',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Advice'),
                        selected: advice,
                        onSelected: requestDisabled
                            ? null
                            : (_) => controller.setCategoryMode(false),
                      ),
                      ChoiceChip(
                        label: const Text('Create category'),
                        selected: controller.categoryMode,
                        onSelected: requestDisabled
                            ? null
                            : (_) => controller.setCategoryMode(true),
                      ),
                      ChoiceChip(
                        label: const Text('Update budget'),
                        selected: controller.budgetMode,
                        onSelected: requestDisabled
                            ? null
                            : (_) => controller.setMode(AdvisorMode.budget),
                      ),
                      ChoiceChip(
                        label: const Text('Add expense'),
                        selected: controller.expenseMode,
                        onSelected: requestDisabled
                            ? null
                            : (_) => controller.setMode(AdvisorMode.expense),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (advice)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final entry in const {
                            'This month': 'Summarize my spending this month.',
                            'Top categories':
                                'Which categories have the highest spending?',
                            'After bills': 'What budget remains after my recorded pending bills?',
                            'Goals · සිංහල': 'Explain my active savings goal progress in Sinhala.',
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: Text(entry.key),
                                onPressed: disabled
                                    ? null
                                    : () {
                                        controller.setDraft(entry.value);
                                      },
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('advisor-question'),
                    controller: _question,
                    onChanged: controller.setDraft,
                    enabled: !requestDisabled,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 1000,
                    scrollPadding: const EdgeInsets.all(32),
                    decoration: InputDecoration(
                      hintText: switch (controller.mode) {
                        AdvisorMode.advice => 'Ask about your spending…',
                        AdvisorMode.category => 'Gym කියලා category එකක් හදන්න',
                        AdvisorMode.budget =>
                          'Set this month’s Food budget to Rs. 8,000',
                        AdvisorMode.expense =>
                          'Add lunch Rs. 650 to Food today using cash',
                      },
                      labelText: advice ? 'Your question' : 'Action request',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: requestDisabled
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            unawaited(controller.send());
                          },
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(switch (controller.mode) {
                      AdvisorMode.advice => 'Ask Ripple',
                      AdvisorMode.category => 'Preview category',
                      AdvisorMode.budget => 'Preview budget',
                      AdvisorMode.expense => 'Preview expense',
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.expenseMode
                        ? 'Preview sends your request to Gemini to extract expense details. '
                              'An omitted date uses today and omitted payment uses Cash. '
                              'Review all fields before confirming.'
                        : controller.budgetMode
                        ? 'Review the month, limit and amount before saving.'
                        : controller.categoryMode
                        ? 'Preview sends only your request to Gemini to extract a name. '
                              'No record is created until you press Confirm create.'
                        : 'Ask sends your question, financial summaries and category, '
                              'bill and active goal names to Gemini. Expense titles and '
                              'notes are excluded. Each question is independent.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (controller.busy) ...[
                    const SizedBox(height: 16),
                    RippleReveal(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF29CDE7)),
                        ),
                        child: const Row(
                          children: [
                            RippleMark(size: 32),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text('Ripple is finding your flow…'),
                            ),
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text('${controller.stage}…'),
                    ),
                  ],
                  if (controller.error != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        controller.error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                    if (advice && !disabled)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => unawaited(controller.refresh()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry loading data'),
                        ),
                      ),
                  ],
                  if (!advice && controller.actionMessage != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(controller.actionMessage!),
                    ),
                  ],
                  if (controller.categoryMode &&
                      controller.pendingCategory != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Review new category',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text('Name: ${controller.pendingCategory!.name}'),
                            const Text(
                              'Action: Create one active expense category',
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: disabled
                                      ? null
                                      : () => unawaited(
                                          controller.confirmCategory(),
                                        ),
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                    controller.busy &&
                                            controller.stage ==
                                                'Saving category'
                                        ? 'Saving…'
                                        : controller.saveAttempted
                                        ? 'Retry confirm'
                                        : 'Confirm create',
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: disabled
                                      ? null
                                      : controller.cancelCategory,
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (controller.budgetMode && budget != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Review budget update',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text('${budget.monthKey} · ${budget.targetName}'),
                            _amountRow('Current limit', budget.previousMinor),
                            _amountRow('Proposed limit', budget.proposedMinor),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: disabled
                                      ? null
                                      : () => unawaited(
                                          controller.confirmBudget(),
                                        ),
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                    controller.busy
                                        ? 'Saving…'
                                        : controller.saveAttempted
                                        ? 'Retry confirm'
                                        : 'Confirm update',
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: disabled
                                      ? null
                                      : controller.cancelBudget,
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (controller.expenseMode && expense != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Review new expense',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text('Title: ${expense.expense.title}'),
                            _amountRow('Amount', expense.expense.amountMinor),
                            Text('Category: ${expense.categoryName}'),
                            Text(
                              'Date: ${expense.dateLabel}'
                              '${expense.defaultDate ? ' (today)' : ''}',
                            ),
                            Text(
                              'Payment: ${expense.expense.paymentMethod}'
                              '${expense.defaultPayment ? ' (default)' : ''}',
                            ),
                            const Text('Note: Empty'),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: disabled
                                      ? null
                                      : () => unawaited(
                                          controller.confirmExpense(),
                                        ),
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                    controller.busy
                                        ? 'Saving…'
                                        : controller.saveAttempted
                                        ? 'Retry confirm'
                                        : 'Confirm expense',
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: disabled
                                      ? null
                                      : controller.cancelExpense,
                                  child: Text(
                                    controller.saveAttempted
                                        ? 'Dismiss preview'
                                        : 'Cancel',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (advice && controller.answer != null) ...[
                    const SizedBox(height: 16),
                    RippleAnswerCard(
                      key: ValueKey(
                        '${controller.answeredQuestion}:${controller.answer}',
                      ),
                      question: controller.answeredQuestion ?? '',
                      answer: controller.answer!,
                    ),
                  ],
                  if (advice && controller.snapshot != null) ...[
                    const SizedBox(height: 12),
                    _facts(controller.snapshot!),
                  ],
                  if (advice && !controller.busy && controller.sessionValid)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => unawaited(controller.refresh()),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Refresh recorded data'),
                      ),
                    ),
                  Text(
                    'The last question and answer stay in memory while you are '
                    'signed in. This app does not save them to Firestore.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Keyboard insets reduce the available sheet area; the body remains scrollable
/// even in a short viewport. The supplied scroll controller supports resizing.
class GeminiAdvisorSheet extends StatelessWidget {
  final GeminiAdvisorController controller;

  const GeminiAdvisorSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.40,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.62],
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: GeminiAdvisorPanel(
          controller: controller,
          scrollController: scrollController,
          compact: true,
          onExpand: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(true);
          },
          onClose: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(false);
          },
        ),
      ),
    ),
  );
}
