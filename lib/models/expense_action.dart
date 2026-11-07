import 'dart:convert';

import 'expense.dart';

class ExpenseActionInput {
  final String instruction;
  final int amountMinor;
  final DateTime date;
  final bool explicitDate;

  const ExpenseActionInput._(
    this.instruction,
    this.amountMinor,
    this.date,
    this.explicitDate,
  );

  factory ExpenseActionInput.parse(String request, {required DateTime now}) {
    if (request.trim().isEmpty || request.length > 1000) {
      throw const FormatException('Enter a request of 1–1000 characters.');
    }
    final dates = RegExp(r'\b\d{4}-\d{2}-\d{2}\b')
        .allMatches(request).toList();
    if (dates.length > 1) {
      throw const FormatException('Use one expense date in YYYY-MM-DD format.');
    }
    final today = DateTime(now.year, now.month, now.day);
    var date = today;
    var instruction = request.trim();
    if (dates.isNotEmpty) {
      final literal = dates.single.group(0)!;
      final parts = literal.split('-').map(int.parse).toList();
      date = DateTime(parts[0], parts[1], parts[2]);
      if (date.year != parts[0] || date.month != parts[1] || date.day != parts[2]) {
        throw const FormatException('Enter a valid date in YYYY-MM-DD format.');
      }
      instruction = request
          .replaceRange(dates.single.start, dates.single.end, ' ').trim();
    }
    if (date.year < 2000 || date.isAfter(today)) {
      throw const FormatException('Use a date from 2000 through today.');
    }
    final amounts = RegExp(r'\d[\d,.]*').allMatches(instruction).toList();
    if (amounts.length != 1 ||
        RegExp(r'[\$€£]|\b(?:USD|EUR|GBP|INR|AUD|CAD|JPY)\b', caseSensitive: false)
            .hasMatch(instruction)) {
      throw const FormatException('Specify one expense amount in rupees.');
    }
    final amount = amounts.single;
    final literal = amount.group(0)!.replaceFirst(RegExp(r'[.,]$'), '');
    final prefix = instruction.substring(0, amount.start)
        .replaceFirst(RegExp(r'(?:Rs\.?|LKR)\s*$', caseSensitive: false), '');
    final suffix = instruction.substring(amount.end);
    if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(literal) ||
        RegExp(r'[-−+.,]\s*$').hasMatch(prefix) ||
        RegExp(r'^\s*[%/]|^[a-zA-Z0-9]|^\s*(?:k|m|million|thousand)\b', caseSensitive: false)
            .hasMatch(suffix)) {
      throw const FormatException('Use a positive rupee amount such as 650 or 1,250.50.');
    }
    final parts = literal.replaceAll(',', '').split('.');
    final rupees = int.tryParse(parts.first);
    if (rupees == null || rupees > 999999999) {
      throw const FormatException('The expense amount exceeds the supported range.');
    }
    final cents = parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0;
    final minor = rupees * 100 + cents;
    if (minor <= 0) {
      throw const FormatException('The expense amount must be greater than zero.');
    }
    return ExpenseActionInput._(instruction, minor, date, dates.isNotEmpty);
  }
}

class ExpenseActionPlan {
  final String title;
  final String category;
  final String paymentMethod;
  final bool defaultPayment;

  const ExpenseActionPlan._(
    this.title,
    this.category,
    this.paymentMethod,
    this.defaultPayment,
  );

  static ExpenseActionPlan? parse(String response, ExpenseActionInput input) {
    final data = jsonDecode(response);
    if (data is! Map<String, dynamic> || data.length != 5 ||
        !['intent', 'title', 'category', 'paymentMethod', 'dateReference']
            .every((key) => data[key] is String)) {
      throw const FormatException('The expense proposal could not be read.');
    }
    if (data['intent'] == 'unsupported') return null;
    final title = (data['title'] as String).trim();
    final category = (data['category'] as String).trim();
    final payment = data['paymentMethod'] as String;
    final expectedDate = input.explicitDate ? 'explicit' : 'today';
    if (data['intent'] != 'createExpense' || data['dateReference'] != expectedDate ||
        title.isEmpty || title.length > 120 || category.isEmpty || category.length > 60 ||
        !input.instruction.toLowerCase().contains(title.toLowerCase()) ||
        !input.instruction.toLowerCase().contains(category.toLowerCase()) ||
        !['cash', 'card', 'bank', 'unspecified'].contains(payment)) {
      throw const FormatException(
        'Include one title and an active category name. Use today or YYYY-MM-DD for the date.',
      );
    }
    return ExpenseActionPlan._(
      title,
      category,
      payment == 'unspecified' ? 'cash' : payment,
      payment == 'unspecified',
    );
  }
}

class ExpenseActionPreview {
  final String userId;
  final Expense expense;
  final String categoryName;
  final bool defaultPayment;
  final bool defaultDate;

  const ExpenseActionPreview({
    required this.userId,
    required this.expense,
    required this.categoryName,
    required this.defaultPayment,
    required this.defaultDate,
  });

  String get dateLabel => '${expense.expenseDate.year}-'
      '${expense.expenseDate.month.toString().padLeft(2, '0')}-'
      '${expense.expenseDate.day.toString().padLeft(2, '0')}';

  void validate(String owner, DateTime now) {
    final date = expense.expenseDate;
    if (userId != owner ||
        !RegExp(r'^advisor_[A-Za-z0-9]{20}$').hasMatch(expense.id) ||
        expense.title.trim().isEmpty || expense.title.length > 120 ||
        expense.amountMinor <= 0 || expense.amountMinor > 99999999999 ||
        expense.categoryId.trim().isEmpty || expense.categoryId.contains('/') ||
        categoryName.trim().isEmpty ||
        !['cash', 'card', 'bank'].contains(expense.paymentMethod) ||
        expense.note.isNotEmpty || date != DateTime(date.year, date.month, date.day) ||
        date.year < 2000 || date.isAfter(DateTime(now.year, now.month, now.day))) {
      throw StateError('This expense preview is invalid. Prepare it again.');
    }
  }
}

class ExpensePreviewChanged implements Exception {
  const ExpensePreviewChanged();
}
