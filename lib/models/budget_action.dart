import 'dart:convert';

import 'monthly_budget.dart';

class BudgetActionInput {
  final DateTime month;
  final int amountMinor;
  final String instruction;

  const BudgetActionInput._(this.month, this.amountMinor, this.instruction);

  factory BudgetActionInput.parse(String request, {required DateTime now}) {
    final datePattern = RegExp(r'\b(\d{4})-(\d{2})\b');
    final dates = datePattern.allMatches(request).toList();
    if (dates.length > 1) {
      throw const FormatException('Enter one budget month in YYYY-MM format.');
    }
    var month = DateTime(now.year, now.month);
    if (dates.isNotEmpty) {
      final year = int.parse(dates.single.group(1)!);
      final number = int.parse(dates.single.group(2)!);
      if (year < 2000 || number < 1 || number > 12) {
        throw const FormatException('Enter a valid month in YYYY-MM format.');
      }
      month = DateTime(year, number);
    }
    final instruction = request.replaceAll(datePattern, ' ').trim();
    final amounts = RegExp(r'\d[\d,.]*').allMatches(instruction).toList();
    if (amounts.length != 1 ||
        RegExp(
          r'[\$€£]|\b(?:USD|EUR|GBP|INR|AUD|CAD|JPY)\b',
          caseSensitive: false,
        ).hasMatch(instruction)) {
      throw const FormatException(
        'Enter one amount in rupees and an optional YYYY-MM month.',
      );
    }
    final amount = amounts.single;
    final literal = amount.group(0)!.replaceFirst(RegExp(r'[.,]$'), '');
    final prefix = instruction
        .substring(0, amount.start)
        .replaceFirst(RegExp(r'(?:Rs\.?|LKR)\s*$', caseSensitive: false), '');
    final suffix = instruction.substring(amount.end);
    if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$')
            .hasMatch(literal) ||
        RegExp(r'[-−+.,]\s*$').hasMatch(prefix) ||
        RegExp(
          r'^\s*[%/]|^[a-zA-Z0-9]|^\s*(?:k|m|million|thousand)\b',
          caseSensitive: false,
        ).hasMatch(suffix)) {
      throw const FormatException(
        'Use a positive rupee amount such as 8000 or 8,000.50.',
      );
    }
    final parts = literal.replaceAll(',', '').split('.');
    final rupees = int.tryParse(parts.first);
    if (rupees == null || rupees > 999999999) {
      throw const FormatException(
        'The budget amount exceeds the supported range.',
      );
    }
    final cents = parts.length == 2
        ? int.parse(parts.last.padRight(2, '0'))
        : 0;
    final minor = rupees * 100 + cents;
    if (minor <= 0)
      throw const FormatException('The budget must be greater than zero.');
    return BudgetActionInput._(month, minor, instruction);
  }
}

class BudgetActionTarget {
  final String? category;

  const BudgetActionTarget._(this.category);

  static BudgetActionTarget? parse(String response, String instruction) {
    final data = jsonDecode(response);
    if (data is! Map<String, dynamic> ||
        data.length != 2 ||
        data['scope'] is! String ||
        data['category'] is! String) {
      throw const FormatException('The budget proposal could not be read.');
    }
    final category = (data['category'] as String).trim();
    switch (data['scope']) {
      case 'overall':
        if (category.isEmpty) return const BudgetActionTarget._(null);
        break;
      case 'category':
        if (category.isNotEmpty &&
            category.length <= 60 &&
            instruction.toLowerCase().contains(category.toLowerCase())) {
          return BudgetActionTarget._(category);
        }
        break;
      case 'unsupported':
        if (category.isEmpty) return null;
        break;
    }
    throw const FormatException(
      'Specify one overall limit or an exact category name.',
    );
  }
}

class BudgetActionPreview {
  final String userId;
  final DateTime month;
  final String? categoryId;
  final String? categoryName;
  final int? previousMinor;
  final int proposedMinor;

  const BudgetActionPreview({
    required this.userId,
    required this.month,
    required this.previousMinor,
    required this.proposedMinor,
    this.categoryId,
    this.categoryName,
  });

  String get monthKey => MonthlyBudget.monthKey(month);
  String get targetName => categoryName ?? 'Overall monthly limit';
}

class BudgetPreviewChanged implements Exception {
  const BudgetPreviewChanged();
}
