import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../services/category_service.dart';
import '../widgets/category_name_dialog.dart';

class CategoryManagerScreen extends StatefulWidget {
  final String userId;

  const CategoryManagerScreen({super.key, required this.userId});

  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {
  late final CategoryService _service;
  late final Stream<List<ExpenseCategory>> _categoriesStream;

  bool _initializing = true;
  bool _busy = false;
  String? _setupError;

  @override
  void initState() {
    super.initState();

    _service = CategoryService(userId: widget.userId);
    _categoriesStream = _service.watchCategories();

    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _initializing = true;
      _setupError = null;
    });

    try {
      await _service.ensureDefaultCategories();
    } catch (error) {
      debugPrint('Category setup failed: $error');

      if (mounted) {
        setState(() {
          _setupError = 'Could not prepare categories. Please retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await action();
    } catch (error) {
      debugPrint('Category action failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the change. Please retry.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editName([ExpenseCategory? category]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => CategoryNameDialog(initialName: category?.name),
    );

    if (!mounted || name == null) return;

    await _runAction(() async {
      if (category == null) {
        await _service.createCategory(name);
      } else {
        await _service.renameCategory(category.id, name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _initializing || _busy || _setupError != null
            ? null
            : () => _editName(),
        icon: const Icon(Icons.add),
        label: const Text('New Category'),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _setupError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_setupError!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _initialize,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : StreamBuilder<List<ExpenseCategory>>(
              stream: _categoriesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Could not load categories.'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final categories = snapshot.data!;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Archived categories stay in your history '
                        'and can be restored.',
                      ),
                    ),
                    if (categories.isEmpty)
                      const Text('Create your first category.'),
                    ...categories.map(
                      (category) => Card(
                        child: ListTile(
                          leading: Icon(
                            category.archived
                                ? Icons.archive_outlined
                                : Icons.category_outlined,
                          ),
                          title: Text(category.name),
                          subtitle: Text(
                            category.archived ? 'Archived' : 'Active',
                          ),
                          trailing: PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (action) async {
                              if (action == 'rename') {
                                await _editName(category);
                              } else {
                                await _runAction(
                                  () => _service.setArchived(
                                    category.id,
                                    !category.archived,
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(
                                  category.archived ? 'Restore' : 'Archive',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
