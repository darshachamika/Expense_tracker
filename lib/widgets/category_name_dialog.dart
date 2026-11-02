import 'package:flutter/material.dart';

class CategoryNameDialog extends StatefulWidget {
  final String? initialName;

  const CategoryNameDialog({super.key, this.initialName});

  @override
  State<CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _controller;

  bool get _isEditing => widget.initialName != null;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.initialName ?? '');
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(context, _controller.text.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Rename category' : 'Create category'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'e.g. Photography',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Enter a category name.';
            }

            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Rename' : 'Create'),
        ),
      ],
    );
  }
}
