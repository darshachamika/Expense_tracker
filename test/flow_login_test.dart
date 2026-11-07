import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/screens/login_screen.dart';
import 'package:expense_tracker/services/auth_service.dart';

class FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuth implements AuthService {
  int emails = 0, registrations = 0, google = 0, resets = 0;
  String? lastEmail, lastPassword;
  @override
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    emails++;
    lastEmail = email.trim();
    lastPassword = password;
    return FakeCredential();
  }

  @override
  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    registrations++;
    return FakeCredential();
  }

  @override
  Future<UserCredential?> signInWithGoogle() async {
    google++;
    return null;
  }

  @override
  Future<void> resetPassword(String email) async {
    resets++;
    lastEmail = email.trim();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('email form validates before sending credentials', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LoginScreen(authService: auth),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pump();
    expect(auth.emails, 0);
    expect(find.text('Enter your email address.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'chami@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'Safe-password-123',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(auth.emails, 1);
    expect(auth.lastEmail, 'chami@example.com');
    expect(auth.lastPassword, 'Safe-password-123');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Google sign in works without filling the email form', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LoginScreen(authService: auth),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(auth.google, 1);
    expect(auth.emails, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account creation requires matching passwords', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LoginScreen(authService: auth),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'chami@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'Safe-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-confirm')),
      'different-password',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(auth.registrations, 0);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('auth-confirm')),
      'Safe-password-123',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(auth.registrations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password reset uses email only', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LoginScreen(authService: auth),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-password')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'chami@example.com',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(auth.resets, 1);
    expect(find.textContaining('If an account exists'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
