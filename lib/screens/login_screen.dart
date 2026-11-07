import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/flow_theme.dart';
import '../widgets/flow_glowing_logo.dart';
import '../widgets/google_sign_in_mark.dart';
import '../widgets/flow_auth_water_background.dart';

enum _AuthMode { signIn, createAccount, reset }

class LoginScreen extends StatefulWidget {
  final AuthService? authService;
  const LoginScreen({super.key, this.authService});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthService _auth = widget.authService ?? AuthService();
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _loading = false, _obscure = true;
  String? _error, _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _changeMode(_AuthMode mode) {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    _form.currentState?.reset();
    setState(() {
      _mode = mode;
      _error = null;
      _notice = null;
      _password.clear();
      _confirm.clear();
      _obscure = true;
    });
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))
      return 'Enter a valid email address.';
    return null;
  }

  String _errorMessage(FirebaseAuthException error) => switch (error.code) {
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'wrong-password' ||
    'user-not-found' => 'Invalid email or password.',
    'email-already-in-use' =>
      'An account already uses this email. Sign in or reset your password.',
    'weak-password' =>
      'Choose a stronger password that meets your account requirements.',
    'invalid-email' => 'Enter a valid email address.',
    'operation-not-allowed' => 'This sign-in method is not enabled yet.',
    'user-disabled' => 'This account is disabled. Contact support.',
    'too-many-requests' => 'Too many attempts. Please try again later.',
    'network-request-failed' => 'Check your internet connection and try again.',
    'popup-closed-by-user' ||
    'cancelled-popup-request' => 'Sign-in canceled. You can try again.',
    'popup-blocked' =>
      'Allow the Google sign-in popup in your browser, then retry.',
    'account-exists-with-different-credential' =>
      'Use your existing sign-in method for this email.',
    _ => 'Could not complete this request. Please try again.',
  };

  Future<void> _submit({bool google = false}) async {
    if (_loading) return;
    if (!google && !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      if (google) {
        await _auth.signInWithGoogle();
      } else if (_mode == _AuthMode.signIn) {
        await _auth.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
      } else if (_mode == _AuthMode.createAccount) {
        await _auth.createAccount(email: _email.text, password: _password.text);
      } else {
        await _auth.resetPassword(_email.text);
        if (mounted)
          setState(
            () => _notice = 'If an account exists for this email, a password reset link has been sent. Check your inbox and spam folder.',
          );
      }
      // AuthGate responds to successful sign-in and account creation.
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      if (_mode == _AuthMode.reset && error.code == 'user-not-found') {
        setState(
          () => _notice = 'If an account exists for this email, a password reset link has been sent. Check your inbox and spam folder.',
        );
      } else {
        setState(() => _error = _errorMessage(error));
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Could not complete this request. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _message(String text, bool error) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFFEEF0) : const Color(0xFFE2F5FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: error ? const Color(0xFFB02139) : FlowTheme.ink,
            fontSize: 13,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final register = _mode == _AuthMode.createAccount;
    final reset = _mode == _AuthMode.reset;
    final title = reset
        ? 'Reset password'
        : register
        ? 'Create account'
        : 'Sign in';
    // The welcome screen keeps the approved icy-white/blue brand in every theme.
    return Theme(
      data: FlowTheme.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4FCFF),
        body: Stack(
          children: [
            const Positioned.fill(child: FlowAuthWaterBackground()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (viewport.maxHeight - 48)
                          .clamp(0.0, double.infinity)
                          .toDouble(),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 390),
                        child: AutofillGroup(
                          child: Form(
                            key: _form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Center(child: FlowGlowingLogo(size: 76)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Flow',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 46,
                                    height: 1,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -2,
                                    color: FlowTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Money, in a better flow.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: FlowTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 30),
                                if (_mode != _AuthMode.signIn) ...[
                                  Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    reset
                                        ? 'Enter your account email to receive a reset link.'
                                        : 'Start building better money habits.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                TextFormField(
                                  key: const ValueKey('auth-email'),
                                  controller: _email,
                                  enabled: !_loading,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: reset
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Email address',
                                    prefixIcon: Icon(
                                      Icons.mail_outline_rounded,
                                    ),
                                  ),
                                  validator: _validateEmail,
                                  onFieldSubmitted: reset
                                      ? (_) {
                                          _submit();
                                        }
                                      : null,
                                ),
                                if (!reset) ...[
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    key: const ValueKey('auth-password'),
                                    controller: _password,
                                    enabled: !_loading,
                                    obscureText: _obscure,
                                    autofillHints: [
                                      register
                                          ? AutofillHints.newPassword
                                          : AutofillHints.password,
                                    ],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textInputAction: register
                                        ? TextInputAction.next
                                        : TextInputAction.done,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _obscure
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: _loading
                                            ? null
                                            : () => setState(
                                                () => _obscure = !_obscure,
                                              ),
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'Enter your password.';
                                      if (register && v.length < 6)
                                        return 'Use at least 6 characters.';
                                      return null;
                                    },
                                    onFieldSubmitted: register
                                        ? null
                                        : (_) {
                                            _submit();
                                          },
                                  ),
                                ],
                                if (register) ...[
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    key: const ValueKey('auth-confirm'),
                                    controller: _confirm,
                                    enabled: !_loading,
                                    obscureText: _obscure,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    decoration: const InputDecoration(
                                      labelText: 'Confirm password',
                                      prefixIcon: Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                    ),
                                    validator: (v) => v != _password.text
                                        ? 'Passwords do not match.'
                                        : null,
                                    onFieldSubmitted: (_) {
                                      _submit();
                                    },
                                  ),
                                ],
                                if (_mode == _AuthMode.signIn)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _loading
                                          ? null
                                          : () => _changeMode(_AuthMode.reset),
                                      child: const Text('Forgot password?'),
                                    ),
                                  )
                                else
                                  const SizedBox(height: 20),
                                if (_error != null) _message(_error!, true),
                                if (_notice != null) _message(_notice!, false),
                                const SizedBox(height: 12),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        FlowTheme.aqua,
                                        Color(0xFF0078FF),
                                        FlowTheme.blue,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: FlowTheme.blue.withValues(
                                          alpha: .19,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 7),
                                      ),
                                    ],
                                  ),
                                  child: FilledButton(
                                    key: const ValueKey('auth-submit'),
                                    onPressed: _loading
                                        ? null
                                        : () => _submit(),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      disabledBackgroundColor:
                                          Colors.transparent,
                                      minimumSize: const Size.fromHeight(50),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(title),
                                  ),
                                ),
                                if (!reset) ...[
                                  const SizedBox(height: 22),
                                  const Row(
                                    children: [
                                      Expanded(child: Divider()),
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        child: Text(
                                          'or',
                                          style: TextStyle(
                                            color: Color(0xFF697A96),
                                          ),
                                        ),
                                      ),
                                      Expanded(child: Divider()),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _submit(google: true),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Color(0xFF747775),
                                      ),
                                      minimumSize: const Size.fromHeight(50),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        GoogleSignInMark(),
                                        SizedBox(width: 12),
                                        Flexible(
                                          child: Text(
                                            'Continue with Google',
                                            style: TextStyle(
                                              color: Color(0xFF1F1F1F),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      _mode == _AuthMode.signIn
                                          ? 'New to Flow?'
                                          : register
                                          ? 'Already have an account?'
                                          : 'Remember your password?',
                                      style: const TextStyle(
                                        color: Color(0xFF65758C),
                                        fontSize: 13,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _loading
                                          ? null
                                          : () => _changeMode(
                                              _mode == _AuthMode.signIn
                                                  ? _AuthMode.createAccount
                                                  : _AuthMode.signIn,
                                            ),
                                      child: Text(
                                        _mode == _AuthMode.signIn
                                            ? 'Create account'
                                            : 'Sign in',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
