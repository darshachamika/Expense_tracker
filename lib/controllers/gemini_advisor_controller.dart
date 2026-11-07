import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/advisor_snapshot.dart';
import '../models/budget_action.dart';
import '../models/category_action.dart';
import '../models/expense_action.dart';
import '../services/advisor_expense_service.dart';
import '../services/gemini_expense_planner.dart';
import '../services/advisor_budget_service.dart';
import '../services/gemini_budget_planner.dart';
import '../services/advisor_category_service.dart';
import '../services/gemini_category_planner.dart';
import '../services/advisor_data_service.dart';
import '../services/gemini_advisor_service.dart';

typedef AdvisorLoader = Future<AdvisorSnapshot> Function();
typedef AdvisorAnswer = Future<String> Function({
  required String question,
  required AdvisorSnapshot snapshot,
});

typedef CategoryPlanner = Future<CategoryPlan> Function(String request);
typedef CategoryLookup = Future<CategoryActionResult?> Function(String name);
typedef CategoryExecutor = Future<CategoryActionResult> Function(
  CategoryActionPreview preview,
);

typedef BudgetPlanner = Future<BudgetActionTarget?> Function(
  String instruction,
);
typedef BudgetPreviewBuilder = Future<BudgetActionPreview> Function(
  BudgetActionInput input,
  BudgetActionTarget target,
);
typedef BudgetExecutor = Future<bool> Function(BudgetActionPreview preview);

typedef ExpensePlanner = Future<ExpenseActionPlan?> Function(
  ExpenseActionInput input,
);
typedef ExpensePreviewBuilder = Future<ExpenseActionPreview> Function(
  ExpenseActionInput input,
  ExpenseActionPlan plan,
);
typedef ExpenseExecutor = Future<bool> Function(ExpenseActionPreview preview);

enum AdvisorMode { advice, category, budget, expense }

/// Owned by the signed-in Home screen, not by a temporary bottom-sheet route.
/// Closing/reopening or expanding a panel therefore retains the same state.
class GeminiAdvisorController extends ChangeNotifier {
  final String userId;
  final AdvisorLoader _load;
  final AdvisorAnswer _ask;
  final CategoryPlanner? _planCategory;
  final CategoryLookup? _findCategory;
  final CategoryExecutor? _createCategory;
  final BudgetPlanner? _planBudget;
  final BudgetPreviewBuilder? _buildBudgetPreview;
  final BudgetExecutor? _saveBudget;
  final ExpensePlanner? _planExpense;
  final ExpensePreviewBuilder? _buildExpensePreview;
  final ExpenseExecutor? _saveExpense;
  ExpenseActionPreview? _pendingExpense;
  AdvisorMode _mode = AdvisorMode.advice;
  BudgetActionPreview? _pendingBudget;
  CategoryActionPreview? _pendingCategory;
  String? _actionMessage;
  bool _saveAttempted = false;

  bool get expenseMode => _mode == AdvisorMode.expense;
  ExpenseActionPreview? get pendingExpense => _pendingExpense;
  bool get expenseRetryRequired => _pendingExpense != null && _saveAttempted;

  AdvisorMode get mode => _mode;
  bool get categoryMode => _mode == AdvisorMode.category;
  bool get budgetMode => _mode == AdvisorMode.budget;
  BudgetActionPreview? get pendingBudget => _pendingBudget;
  CategoryActionPreview? get pendingCategory => _pendingCategory;
  String? get actionMessage => _actionMessage;
  bool get saveAttempted => _saveAttempted;
  String _draft = '';
  String get draft => _draft;
  StreamSubscription<String?>? _sessionSubscription;
  bool _disposed = false;
  bool _initialLoadStarted = false;
  int _request = 0;

  AdvisorSnapshot? _snapshot;
  String? _answer;
  String? _answeredQuestion;
  String? _error;
  String _stage = 'Loading recorded data';
  bool _busy = false;
  bool _sessionValid;

  AdvisorSnapshot? get snapshot => _snapshot;
  String? get answer => _answer;
  String? get answeredQuestion => _answeredQuestion;
  String? get error => _error;
  String get stage => _stage;
  bool get busy => _busy;
  bool get sessionValid => _sessionValid;

  /// Injectable functions let lifecycle tests run without Firebase requests.
  GeminiAdvisorController({
    required this.userId,
    required AdvisorLoader load,
    required AdvisorAnswer ask,
    required String? initialUserId,
    Stream<String?>? sessionChanges,
    CategoryPlanner? planCategory,
    CategoryLookup? findCategory,
    CategoryExecutor? createCategory,
    BudgetPlanner? planBudget,
    BudgetPreviewBuilder? buildBudgetPreview,
    BudgetExecutor? saveBudget,
    ExpensePlanner? planExpense,
    ExpensePreviewBuilder? buildExpensePreview,
    ExpenseExecutor? saveExpense,
  }) : _load = load,
       _ask = ask,
       _planCategory = planCategory,
       _findCategory = findCategory,
       _createCategory = createCategory,
       _planBudget = planBudget,
       _buildBudgetPreview = buildBudgetPreview,
       _saveBudget = saveBudget,
       _planExpense = planExpense,
       _buildExpensePreview = buildExpensePreview,
       _saveExpense = saveExpense,
       _sessionValid = initialUserId == userId {
    if (!_sessionValid) {
      _error = 'Your session changed. Close the advisor and sign in again.';
    }
    _sessionSubscription = sessionChanges?.listen((uid) {
      if (uid != userId) invalidateSession();
    });
  }

  factory GeminiAdvisorController.forUser(String userId) {
    final auth = FirebaseAuth.instance;
    final data = AdvisorDataService(userId: userId);
    final advisor = GeminiAdvisorService(userId: userId);
    final planner = GeminiCategoryPlanner(userId: userId);
    final categories = AdvisorCategoryService(userId: userId);
    final budgetPlanner = GeminiBudgetPlanner(userId: userId);
    final budgets = AdvisorBudgetService(userId: userId);
    final expensePlanner = GeminiExpensePlanner(userId: userId);
    final expenses = AdvisorExpenseService(userId: userId);
    return GeminiAdvisorController(
      userId: userId,
      load: data.load,
      ask: advisor.ask,
      planCategory: planner.plan,
      findCategory: categories.findExisting,
      createCategory: categories.createConfirmed,
      planBudget: budgetPlanner.plan,
      buildBudgetPreview: budgets.preview,
      saveBudget: budgets.confirm,
      planExpense: expensePlanner.plan,
      buildExpensePreview: expenses.preview,
      saveExpense: expenses.confirm,
      initialUserId: auth.currentUser?.uid,
      sessionChanges: auth.authStateChanges().map((user) => user?.uid),
    );
  }

  // Called when a view first opens. This reads data only, never calls Gemini.
  Future<void> ensureLoaded() async {
    if (_initialLoadStarted || _disposed || !_sessionValid) return;
    _initialLoadStarted = true;
    await refresh();
  }

  void setDraft(String value) {
    if (_disposed || !_sessionValid || _busy || expenseRetryRequired ||
        value == _draft) {
      return;
    }
    _draft = value;
    _pendingBudget = null;
    _pendingCategory = null;
    _pendingExpense = null;
    _actionMessage = null;
    _saveAttempted = false;
    notifyListeners();
  }

  Future<void> refresh() => _run(ask: false);
  Future<void> send() => switch (_mode) {
    AdvisorMode.advice => _run(ask: true),
    AdvisorMode.category => _prepareCategory(),
    AdvisorMode.budget => _prepareBudget(),
    AdvisorMode.expense => _prepareExpense(),
  };

  void setCategoryMode(bool value) =>
      setMode(value ? AdvisorMode.category : AdvisorMode.advice);

  void setMode(AdvisorMode value) {
    if (_disposed || !_sessionValid || _busy || expenseRetryRequired ||
        value == _mode) {
      return;
    }
    _mode = value;
    _pendingCategory = null;
    _pendingBudget = null;
    _pendingExpense = null;
    _actionMessage = null;
    _saveAttempted = false;
    _error = null;
    notifyListeners();
  }

  void cancelCategory() {
    if (_disposed || !_sessionValid || _busy || _pendingCategory == null)
      return;
    _pendingCategory = null;
    _actionMessage = _saveAttempted
        ? 'Preview dismissed. If a save was attempted, check Manage Categories. '
              'Dismissing a preview does not undo a save.'
        : 'Cancelled. This preview created no category.';
    _saveAttempted = false;
    _error = null;
    notifyListeners();
  }

  Future<void> _prepareCategory() async {
    if (_disposed || _busy || !_sessionValid) return;
    if (_planCategory == null || _findCategory == null) {
      _error = 'Category actions are not configured.';
      notifyListeners();
      return;
    }
    final input = _draft.trim();
    if (input.isEmpty || input.length > 1000) {
      _error = 'Enter a request of 1–1000 characters.';
      notifyListeners();
      return;
    }
    final request = ++_request;
    _busy = true;
    _error = null;
    _actionMessage = null;
    _pendingCategory = null;
    _saveAttempted = false;
    _stage = 'Preparing category preview';
    notifyListeners();
    try {
      final plan = await _planCategory(input)
          .timeout(const Duration(seconds: 90));
      if (!_isCurrent(request)) return;
      if (plan.intent != CategoryPlanIntent.createCategory) {
        _actionMessage = plan.intent == CategoryPlanIntent.needsName
            ? 'Include one exact category name, for example: Create a category called Gym.'
            : 'This mode supports creating one category only. For advice, select Advice.';
        return;
      }
      final preview = CategoryActionPreview(name: plan.name!, userId: userId);
      _stage = 'Checking existing categories';
      notifyListeners();
      final existing = await _findCategory(preview.name)
          .timeout(const Duration(seconds: 60));
      if (!_isCurrent(request)) return;
      if (existing != null) {
        _actionMessage = _existingMessage(existing);
      } else {
        _pendingCategory = preview;
      }
    } catch (error) {
      debugPrint('Category preview failed (${error.runtimeType}).');
      if (_isCurrent(request)) _error = _errorText(error);
    } finally {
      if (_isCurrent(request)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  String _existingMessage(CategoryActionResult result) => result.archived
      ? 'Category "${result.name}" already exists and is archived. '
            'Restore it from Manage Categories; no duplicate was created.'
      : 'Category "${result.name}" already exists. No duplicate was created.';

  Future<void> confirmCategory() async {
    final preview = _pendingCategory;
    if (_disposed || !_sessionValid || _busy || preview == null) return;
    if (_createCategory == null || preview.userId != userId) {
      _error = 'This category preview cannot be saved. Prepare it again.';
      notifyListeners();
      return;
    }
    final request = ++_request;
    _busy = true;
    _saveAttempted = true;
    _error = null;
    _stage = 'Saving category';
    notifyListeners();
    try {
      // No UI timeout on a write: keep controls disabled until it completes.
      // The service's stable document ID makes a later explicit retry safe.
      final result = await _createCategory(preview);
      if (!_isCurrent(request)) return;
      _pendingCategory = null;
      _saveAttempted = false;
      _actionMessage = result.created
          ? 'Category created: ${result.name}.'
          : _existingMessage(result);
    } catch (error) {
      debugPrint('Category save failed (${error.runtimeType}).');
      if (_isCurrent(request)) {
        _error =
            '${_errorText(error)} Save could not be confirmed. '
            'Retry this same preview to recheck before creating.';
      }
    } finally {
      if (_isCurrent(request)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void cancelBudget() {
    if (_disposed || !_sessionValid || _busy || _pendingBudget == null) return;
    _pendingBudget = null;
    _actionMessage = _saveAttempted
        ? 'Preview dismissed. Check the monthly budget for the result of any attempted save.'
        : 'Budget preview cancelled.';
    _saveAttempted = false;
    _error = null;
    notifyListeners();
  }

  Future<void> _prepareBudget() async {
    if (_disposed || !_sessionValid || _busy) return;
    final plan = _planBudget;
    final build = _buildBudgetPreview;
    if (plan == null || build == null) return;
    final request = ++_request;
    _pendingBudget = null;
    _actionMessage = null;
    _error = null;
    _saveAttempted = false;
    _busy = true;
    _stage = 'Preparing budget preview';
    notifyListeners();
    try {
      if (_draft.trim().isEmpty || _draft.length > 1000) {
        throw const FormatException('Enter a request of 1–1000 characters.');
      }
      final input = BudgetActionInput.parse(_draft, now: DateTime.now());
      final target = await plan(input.instruction)
          .timeout(const Duration(seconds: 90));
      if (!_isCurrent(request)) return;
      if (target == null) {
        _actionMessage = 'Specify one budget limit in rupees. Use this month or a YYYY-MM date.';
        return;
      }
      final preview = await build(
        input,
        target,
      ).timeout(const Duration(seconds: 60));
      if (_isCurrent(request)) _pendingBudget = preview;
    } catch (error) {
      if (_isCurrent(request)) _error = _errorText(error);
    } finally {
      if (_isCurrent(request)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> confirmBudget() async {
    final preview = _pendingBudget;
    final save = _saveBudget;
    if (_disposed ||
        !_sessionValid ||
        _busy ||
        !budgetMode ||
        preview == null ||
        save == null ||
        preview.userId != userId)
      return;
    final request = ++_request;
    _busy = true;
    _saveAttempted = true;
    _error = null;
    _stage = 'Saving budget limit';
    notifyListeners();
    try {
      final changed = await save(preview);
      if (!_isCurrent(request)) return;
      _pendingBudget = null;
      _saveAttempted = false;
      final amount = advisorMoney(preview.proposedMinor);
      _actionMessage = changed
          ? 'Saved ${preview.targetName} for ${preview.monthKey} at $amount.'
          : '${preview.targetName} for ${preview.monthKey} is already $amount.';
    } on BudgetPreviewChanged {
      if (!_isCurrent(request)) return;
      _pendingBudget = null;
      _saveAttempted = false;
      _error = 'The budget or category changed. Preview the request again before saving.';
    } catch (error) {
      if (_isCurrent(request)) {
        _error =
            '${_errorText(error)} Save could not be confirmed. Retry this preview to recheck it.';
      }
    } finally {
      if (_isCurrent(request)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void cancelExpense() {
    if (_disposed || !_sessionValid || _busy || _pendingExpense == null) return;
    _pendingExpense = null;
    _actionMessage = _saveAttempted
        ? 'Preview dismissed. Check your expense list before submitting again. '
              'An attempted save may already have completed.'
        : 'Expense preview cancelled.';
    _saveAttempted = false;
    _error = null;
    notifyListeners();
  }

  Future<void> _prepareExpense() async {
    if (_disposed || !_sessionValid || _busy || expenseRetryRequired) return;
    final plan = _planExpense;
    final build = _buildExpensePreview;
    if (plan == null || build == null) {
      _error = 'Expense actions are not configured.';
      notifyListeners();
      return;
    }
    final request = ++_request;
    _pendingExpense = null;
    _actionMessage = null;
    _error = null;
    _saveAttempted = false;
    _busy = true;
    _stage = 'Preparing expense preview';
    notifyListeners();
    try {
      final input = ExpenseActionInput.parse(_draft, now: DateTime.now());
      final proposal = await plan(input).timeout(const Duration(seconds: 90));
      if (!_isCurrent(request)) return;
      if (proposal == null) {
        _actionMessage = 'Specify one expense title, rupee amount and active category. '
            'Use today or YYYY-MM-DD. Payment can be cash, card or bank.';
        return;
      }
      final preview = await build(
        input, proposal,
      ).timeout(const Duration(seconds: 60));
      if (!_isCurrent(request)) return;
      preview.validate(userId, DateTime.now());
      _pendingExpense = preview;
    } catch (error) {
      if (_isCurrent(request)) _error = _errorText(error);
    } finally {
      if (_isCurrent(request)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> confirmExpense() async {
    final preview = _pendingExpense;
    final save = _saveExpense;
    if (_disposed || !_sessionValid || _busy || !expenseMode ||
        preview == null || save == null || preview.userId != userId) {
      return;
    }
    final request = ++_request;
    _busy = true;
    _saveAttempted = true;
    _error = null;
    _stage = 'Saving expense';
    notifyListeners();
    try {
      // Keep the original document ID and disable controls until the write ends.
      final created = await save(preview);
      if (!_isCurrent(request)) return;
      _pendingExpense = null;
      _saveAttempted = false;
      _draft = '';
      _snapshot = null;
      _answer = null;
      _answeredQuestion = null;
      _actionMessage = created
          ? 'Expense saved: ${preview.expense.title} · ${advisorMoney(preview.expense.amountMinor)}.'
          : 'This expense preview was already saved. Check your expense list.';
    } on ExpensePreviewChanged {
      if (!_isCurrent(request)) return;
      _pendingExpense = null;
      _saveAttempted = false;
      _error = 'The category changed. Preview the expense again before saving.';
    } catch (error) {
      if (_isCurrent(request)) {
        _error = '${_errorText(error)} Save could not be confirmed. '
            'Retry this same preview to check its result. '
            'Before dismissing it, check your expense list.';
      }
    } finally {
      if (_isCurrent(request)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void invalidateSession() {
    if (_disposed || !_sessionValid) return;
    _request++;
    _sessionValid = false;
    _busy = false;
    _snapshot = null;
    _answer = null;
    _answeredQuestion = null;
    _draft = '';
    _pendingBudget = null;
    _pendingCategory = null;
    _pendingExpense = null;
    _actionMessage = null;
    _saveAttempted = false;
    _error = 'Your session changed. Close the advisor and sign in again.';
    notifyListeners();
  }

  String _errorText(Object error) {
    if (error is TimeoutException) {
      return 'The request timed out. Check your connection and try again.';
    }
    if (error is FirebaseException) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        return 'Access was denied. Check your sign-in and Firebase configuration.';
      }
      return 'Could not complete the request (${error.code}). Try again shortly.';
    }
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message;
    final description = error.toString().toLowerCase();
    if (description.contains('429') || description.contains('quota')) {
      return 'Gemini usage limit reached. Wait before trying again.';
    }
    if (description.contains('403') ||
        description.contains('app check') ||
        description.contains('appcheck')) {
      return 'Gemini access was denied. Check App Check and AI Logic setup.';
    }
    return 'Could not complete the request. Check your connection and AI Logic configuration.';
  }

  bool _isCurrent(int request) =>
      !_disposed && _sessionValid && request == _request;

  Future<void> _run({required bool ask}) async {
    if (_disposed || _busy || !_sessionValid) return;
    final input = _draft.trim();
    if (ask && (input.isEmpty || input.length > 1000)) {
      _error = 'Enter a question of 1–1000 characters.';
      notifyListeners();
      return;
    }
    _initialLoadStarted = true;
    final request = ++_request;
    _busy = true;
    _error = null;
    _stage = 'Loading recorded data';
    // Keep the last successful answer visible until a new Ask is submitted.
    if (ask) {
      _answer = null;
      _answeredQuestion = null;
      _snapshot = null;
    }
    notifyListeners();
    try {
      final snapshot = await _load().timeout(const Duration(seconds: 60));
      if (!_isCurrent(request)) return;
      _snapshot = snapshot;
      notifyListeners();
      if (ask) {
        _stage = 'Asking Gemini';
        notifyListeners();
        final response = await _ask(
          question: input,
          snapshot: snapshot,
        ).timeout(const Duration(seconds: 90));
        if (!_isCurrent(request)) return;
        _answer = response;
        _answeredQuestion = input;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Advisor failed during $_stage (${error.runtimeType}).');
      if (_isCurrent(request)) {
        _error = _errorText(error);
        // A failed refresh must not display an old snapshot as freshly loaded.
        if (_stage == 'Loading recorded data') _snapshot = null;
      }
    } finally {
      if (_isCurrent(request)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionValid = false;
    _busy = false;
    _request++;
    _sessionSubscription?.cancel();
    _snapshot = null;
    _answer = null;
    _answeredQuestion = null;
    _draft = '';
    _pendingBudget = null;
    _pendingCategory = null;
    _pendingExpense = null;
    _actionMessage = null;
    super.dispose();
  }
}
