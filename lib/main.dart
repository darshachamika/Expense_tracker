import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'theme/flow_theme.dart';
import 'widgets/flow_video_launch.dart';
import 'widgets/flow_startup_gate.dart';
import 'widgets/flow_app_water.dart';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ExpenseTrackerApp(initialize: _initializeFirebase));
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Configure App Check for the current Edge/web testing step.
    if (kIsWeb) {
      const siteKey = String.fromEnvironment('APP_CHECK_RECAPTCHA_SITE_KEY');

      if (!kDebugMode && siteKey.isEmpty) {
        throw StateError(
          'APP_CHECK_RECAPTCHA_SITE_KEY is required for web release builds.',
        );
      }

      await FirebaseAppCheck.instance.activate(
        providerWeb: kDebugMode
            ? WebDebugProvider()
            : ReCaptchaV3Provider(siteKey),
      );
    }

    const runGeminiTest = bool.fromEnvironment(
      'RUN_GEMINI_TEST',
      defaultValue: false,
    );

    if (kIsWeb && kDebugMode && runGeminiTest) {
      unawaited(_testGeminiConnection());
    }
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    rethrow;
  }
}

Future<void> _testGeminiConnection() async {
  var stage = 'App Check';

  try {
    debugPrint('GEMINI TEST: requesting App Check token');

    final token = await FirebaseAppCheck.instance.getToken().timeout(
      const Duration(seconds: 180),
    );

    if (token == null || token.isEmpty) {
      throw StateError('App Check returned no token.');
    }

    debugPrint('GEMINI TEST: App Check token received');

    stage = 'Gemini response';

    final model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-3.5-flash-lite',
    );

    debugPrint('GEMINI TEST: sending request');

    final response = await model
        .generateContent([
          Content.text('Reply with only: Connection successful.'),
        ])
        .timeout(const Duration(seconds: 90));

    final text = response.text?.trim();

    if (text == null || text.isEmpty) {
      throw StateError('Gemini returned no text.');
    }

    debugPrint('GEMINI TEST SUCCESS: $text');
  } catch (error) {
    debugPrint('GEMINI TEST FAILED at $stage: $error');
  }
}

class ExpenseTrackerApp extends StatefulWidget {
  final Future<void>? initialization;
  final Future<void> Function()? initialize;
  const ExpenseTrackerApp({super.key, this.initialization, this.initialize});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: FlowTheme.appearance,
      builder: (context, mode, _) => MaterialApp(
        title: 'Flow — Expense Tracker',
        debugShowCheckedModeBanner: false,
        theme: FlowTheme.light,
        darkTheme: FlowTheme.dark,
        themeMode: mode,
        builder: (context, child) =>
            FlowAppWater(child: child ?? const SizedBox.shrink()),
        home: FlowVideoLaunch(
          child: FlowStartupGate(
            initialization: widget.initialization,
            initialize: widget.initialize,
            destination: const AuthGate(),
            errorBuilder: (context, error) => const FirebaseErrorApp(),
          ),
        ),
      ),
    );
  }
}

class SetupSuccessScreen extends StatelessWidget {
  const SetupSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Expense Tracker')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 72, color: colors.primary),
              const SizedBox(height: 20),
              Text(
                'Firebase initialized!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Your app foundation is ready.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FirebaseErrorApp extends StatelessWidget {
  const FirebaseErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Firebase setup could not finish.\n'
              'Check the terminal output, then restart the app.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
