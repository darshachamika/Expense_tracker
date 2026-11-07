import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/budget_action.dart';

class GeminiBudgetPlanner {
  final String userId;
  final GenerativeModel _model;

  GeminiBudgetPlanner({required this.userId})
    : _model = FirebaseAI.googleAI().generativeModel(
        model: const String.fromEnvironment(
          'GEMINI_MODEL',
          defaultValue: 'gemini-3.5-flash-lite',
        ),
        generationConfig: GenerationConfig(
          temperature: 0,
          maxOutputTokens: 1024,
          responseMimeType: 'application/json',
          responseSchema: Schema.object(
            properties: {
              'scope': Schema.enumString(
                enumValues: ['overall', 'category', 'unsupported'],
              ),
              'category': Schema.string(),
            },
          ),
        ),
        systemInstruction: Content.system('''
Classify one instruction to set an expense budget limit. Understand English,
Sinhala and mixed requests. The app parses the amount and any YYYY-MM date.
Return overall only for an explicit overall or total monthly budget.
Return category for a named category limit. Copy the literal category name.
Otherwise return unsupported. Use an empty category for overall or unsupported.
An omitted month or this month means the current month. The app removes an
explicit YYYY-MM date before sending this instruction. Reject other month
references, ambiguous instructions, foreign currencies, multiple actions,
deletion, percentage changes and increases or decreases by an amount.
You only classify; never execute writes or claim success.
'''),
      );

  Future<BudgetActionTarget?> plan(String instruction) async {
    _checkUser();
    final response = await _model.generateContent([
      Content.text(jsonEncode({'instruction': instruction})),
    ]);
    _checkUser();
    final json = response.text;
    if (json == null || json.length > 10000) {
      throw const FormatException('No usable budget proposal was returned.');
    }
    return BudgetActionTarget.parse(json, instruction);
  }

  void _checkUser() {
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Your session changed. Reopen the advisor.');
    }
  }
}
