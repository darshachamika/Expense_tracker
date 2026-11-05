import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/advisor_snapshot.dart';
import '../services/advisor_data_service.dart';
import '../services/gemini_advisor_service.dart';

typedef AdvisorLoader = Future<AdvisorSnapshot> Function();
typedef AdvisorAnswer = Future<String> Function({
  required String question,
  required AdvisorSnapshot snapshot,
});

/// Owned by the signed-in Home screen, not by a temporary bottom-sheet route.
/// Closing/reopening or expanding a panel therefore retains the same state.
class GeminiAdvisorController extends ChangeNotifier {
  final String userId;
  final AdvisorLoader _load;
  final AdvisorAnswer _ask;
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
  }) : _load = load,
       _ask = ask,
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
    return GeminiAdvisorController(
      userId: userId,
      load: data.load,
      ask: advisor.ask,
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
    notifyListeners();
  }

  Future<void> refresh() => _run(ask: false);
  Future<void> send() => _run(ask: true);

  void invalidateSession() {
    if (_disposed || !_sessionValid) return;
    _request++;
    _sessionValid = false;
    _busy = false;
    _snapshot = null;
    _answer = null;
    _answeredQuestion = null;
    _draft = '';
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
    super.dispose();
  }
}
