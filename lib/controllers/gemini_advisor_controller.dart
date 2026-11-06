import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/advisor_snapshot.dart';
import '../models/category_action.dart';
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

/// Owned by the signed-in Home screen, not by a temporary bottom-sheet route.
/// Closing/reopening or expanding a panel therefore retains the same state.
class GeminiAdvisorController extends ChangeNotifier {
  final String userId;
  final AdvisorLoader _load;
  final AdvisorAnswer _ask;
  final CategoryPlanner? _planCategory;
  final CategoryLookup? _findCategory;
  final CategoryExecutor? _createCategory;
  bool _categoryMode = false;
  CategoryActionPreview? _pendingCategory;
  String? _actionMessage;
  bool _saveAttempted = false;

  bool get categoryMode => _categoryMode;
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
  }) : _load = load,
       _ask = ask,
       _planCategory = planCategory,
       _findCategory = findCategory,
       _createCategory = createCategory,
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
    return GeminiAdvisorController(
      userId: userId,
      load: data.load,
      ask: advisor.ask,
      planCategory: planner.plan,
      findCategory: categories.findExisting,
      createCategory: categories.createConfirmed,
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
    if (_disposed || !_sessionValid || _busy || value == _draft) return;
    _draft = value;
    _pendingCategory = null;
    _actionMessage = null;
    _saveAttempted = false;
    notifyListeners();
  }

  Future<void> refresh() => _run(ask: false);
  Future<void> send() => _categoryMode ? _prepareCategory() : _run(ask: true);

  void setCategoryMode(bool value) {
    if (_disposed || !_sessionValid || _busy || value == _categoryMode) return;
    _categoryMode = value;
    _pendingCategory = null;
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

  void invalidateSession() {
    if (_disposed || !_sessionValid) return;
    _request++;
    _sessionValid = false;
    _busy = false;
    _snapshot = null;
    _answer = null;
    _answeredQuestion = null;
    _draft = '';
    _pendingCategory = null;
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
    _pendingCategory = null;
    _actionMessage = null;
    super.dispose();
  }
}
