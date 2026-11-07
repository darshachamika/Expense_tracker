import 'dart:convert';

import 'package:crypto/crypto.dart';

String cleanCategoryActionName(String value) {
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
    throw const FormatException(
      'Category names cannot contain control characters.',
    );
  }
  final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty || clean.length > 60) {
    throw const FormatException('Category name must contain 1–60 characters.');
  }
  return clean;
}

String normalizedCategoryActionName(String value) =>
    cleanCategoryActionName(value).toLowerCase();

String categoryActionDocumentId(String name) =>
    'aicat_${sha256.convert(utf8.encode(normalizedCategoryActionName(name)))}';

enum CategoryPlanIntent { createCategory, needsName, unsupported }

/// Strictly decoded model output. The model cannot specify IDs or write fields.
class CategoryPlan {
  final CategoryPlanIntent intent;
  final String? name;

  const CategoryPlan._(this.intent, this.name);

  factory CategoryPlan.parse(String json, {required String request}) {
    final data = jsonDecode(json);
    if (data is! Map<String, dynamic> ||
        data.length != 2 ||
        !data.containsKey('intent') ||
        !data.containsKey('name') ||
        data['intent'] is! String ||
        data['name'] is! String) {
      throw const FormatException(
        'Invalid category proposal. Try a clearer request.',
      );
    }
    switch (data['intent']) {
      case 'create_category':
        final name = cleanCategoryActionName(data['name'] as String);
        // Require the literal name to occur in the request. Do not silently
        // translate, infer or invent a category name on the user's behalf.
        final text = request
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();
        if (!text.contains(name.toLowerCase())) {
          throw const FormatException(
            'Include the exact category name in your request.',
          );
        }
        return CategoryPlan._(CategoryPlanIntent.createCategory, name);
      case 'needs_name':
        if (data['name'] != '') {
          throw const FormatException('Invalid category proposal.');
        }
        return const CategoryPlan._(CategoryPlanIntent.needsName, null);
      case 'unsupported':
        if (data['name'] != '') {
          throw const FormatException('Invalid category proposal.');
        }
        return const CategoryPlan._(CategoryPlanIntent.unsupported, null);
      default:
        throw const FormatException('Unsupported category proposal.');
    }
  }
}

/// Created locally after validation. Confirm executes this exact immutable name,
/// not a name read again from the editable input or generated a second time.
class CategoryActionPreview {
  final String name;
  final String userId;
  final String documentId;

  CategoryActionPreview({required String name, required this.userId})
    : name = cleanCategoryActionName(name),
      documentId = categoryActionDocumentId(name);
}

class CategoryActionResult {
  final String name;
  final bool created;
  final bool archived;

  const CategoryActionResult({
    required this.name,
    this.created = false,
    this.archived = false,
  });
}
