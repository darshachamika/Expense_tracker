import 'dart:async';

import '../models/flow_profile.dart';
import '../services/profile_service.dart';
import '../theme/flow_theme.dart';
import 'profile_screen.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/expense_category.dart';
import '../services/auth_service.dart';
import '../services/category_service.dart';
import '../services/expense_service.dart';
import 'add_expense_screen.dart';
import 'category_manager_screen.dart';
import 'monthly_budget_screen.dart';
import 'dashboard_screen.dart';
import 'savings_goals_screen.dart';
import 'planned_bills_screen.dart';
import 'purchase_simulator_screen.dart';
import 'gemini_advisor_screen.dart';
import '../controllers/gemini_advisor_controller.dart';
import '../widgets/gemini_advisor_panel.dart';
import '../widgets/flow_visuals.dart';
import '../widgets/ripple_advisor_visuals.dart';
import '../widgets/flow_activity_view.dart';
import '../widgets/flow_format.dart';

class SignedInScreen extends StatefulWidget {
  final User user;

  const SignedInScreen({super.key, required this.user});

  @override
  State<SignedInScreen> createState() => _SignedInScreenState();
}

class _SignedInScreenState extends State<SignedInScreen> {
  final _authService = AuthService();
  final _searchController = TextEditingController();
  late final GeminiAdvisorController _advisorController;
  FlowProfile _profile = const FlowProfile();
  StreamSubscription<FlowProfile>? _profileSubscription;
  bool _profileReady = false;
  String? _profileError;
  bool _advisorOpen = false;
  int _tab = 0;

  String _searchQuery = '';
  String? _filterCategoryId;
  DateTimeRange? _filterDateRange;

  late final ExpenseService _expenseService;
  late final Stream<List<Expense>> _expensesStream;

  StreamSubscription<List<ExpenseCategory>>? _categorySubscription;

  Map<String, ExpenseCategory> _categoriesById = {};

  bool _categoriesLoading = true;
  bool _categoriesFailed = false;
  bool _signingOut = false;
  bool _deletingExpense = false;

  bool get _busy => _signingOut || _deletingExpense;

  bool _isBillPayment(Expense expense) => expense.id.startsWith('bill_');

  @override
  void initState() {
    super.initState();

    _profileSubscription = ProfileService(widget.user.uid).watch().listen(
      (profile) {
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _profileReady = true;
          _profileError = null;
        });
        FlowTheme.appearance.value = switch (profile.appearance) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
      },
      onError: (Object error) {
        if (mounted)
          setState(() {
            _profileError = 'Could not load profile. Check your connection and Firestore permissions.';
            _profileReady = false;
          });
      },
    );
    final now = DateTime.now();
    _filterDateRange = DateTimeRange(
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _advisorController = GeminiAdvisorController.forUser(widget.user.uid);

    _expenseService = ExpenseService(userId: widget.user.uid);
    _expensesStream = _expenseService.watchExpenses();

    _categorySubscription = CategoryService(userId: widget.user.uid)
        .watchCategories()
        .listen(
          (categories) {
            if (!mounted) return;

            setState(() {
              _categoriesById = {
                for (final category in categories) category.id: category,
              };
              _categoriesLoading = false;
              _categoriesFailed = false;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Category names failed to load: $error');

            if (!mounted) return;

            setState(() {
              _categoriesLoading = false;
              _categoriesFailed = true;
            });
          },
        );
  }

  Future<void> _openAdvisor() async {
    if (_busy || _advisorOpen || !_advisorController.sessionValid) return;
    setState(() => _advisorOpen = true);
    try {
      final expand = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(maxWidth: 480),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => RippleReveal(
          child: GeminiAdvisorSheet(controller: _advisorController),
        ),
      );
      if (!mounted || expand != true || !_advisorController.sessionValid) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => GeminiAdvisorScreen(
            userId: widget.user.uid,
            controller: _advisorController,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _advisorOpen = false);
    }
  }

  void _filterToday() {
    final today = DateUtils.dateOnly(DateTime.now());

    setState(() {
      _filterDateRange = DateTimeRange(start: today, end: today);
    });
  }

  void _filterThisMonth() {
    final now = DateTime.now();

    setState(() {
      _filterDateRange = DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      );
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();

    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month + 1, 0),
      initialDateRange: _filterDateRange,
      helpText: 'Select expense dates',
    );

    if (!mounted || selected == null) return;

    setState(() => _filterDateRange = selected);
  }

  List<Expense> _filterExpenses(List<Expense> expenses) {
    final query = _searchQuery.trim().toLowerCase();
    final range = _filterDateRange;

    return expenses.where((expense) {
      final matchesCategory =
          _filterCategoryId == null || expense.categoryId == _filterCategoryId;

      final matchesSearch =
          query.isEmpty ||
          expense.title.toLowerCase().contains(query) ||
          expense.note.toLowerCase().contains(query);

      bool matchesDate = true;

      if (range != null) {
        final date = DateUtils.dateOnly(expense.expenseDate.toLocal());
        final start = DateUtils.dateOnly(range.start);
        final end = DateUtils.dateOnly(range.end);

        matchesDate = !date.isBefore(start) && !date.isAfter(end);
      }

      return matchesCategory && matchesSearch && matchesDate;
    }).toList();
  }

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _filterCategoryId = null;
      _filterDateRange = null;
    });
  }

  String _categoryLabel(String id) {
    final category = _categoriesById[id];

    if (category != null) {
      return category.archived ? '${category.name} (Archived)' : category.name;
    }

    if (_categoriesLoading) return 'Loading category…';
    if (_categoriesFailed) return 'Category unavailable';

    return 'Unknown category';
  }

  String _formatMoney(int amountMinor) {
    final rupees = amountMinor ~/ 100;
    final cents = (amountMinor % 100).toString().padLeft(2, '0');

    return 'Rs. $rupees.$cents';
  }

  Future<void> _addExpense() async {
    if (_busy) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(userId: widget.user.uid),
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expense saved successfully.')),
    );
  }

  Future<void> _editExpense(Expense expense) async {
    if (_busy || _isBillPayment(expense)) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddExpenseScreen(userId: widget.user.uid, expense: expense),
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expense updated successfully.')),
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    if (_busy || _isBillPayment(expense)) return;

    // Lock actions while confirming and deleting.
    setState(() => _deletingExpense = true);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete expense?'),
          content: Text(
            'Delete "${expense.title}" '
            '(${_formatMoney(expense.amountMinor)})?\n\n'
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null || currentUser.uid != widget.user.uid) {
        throw StateError('Your session changed. Please sign in again.');
      }

      await _expenseService.deleteExpense(expense.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted successfully.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Expense deletion failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the expense. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingExpense = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;

    setState(() => _signingOut = true);

    try {
      await _authService.signOut();
    } catch (error) {
      debugPrint('Sign-out failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not finish signing out. Try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _advisorController.dispose();
    _searchController.dispose();
    _categorySubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: _tab == 0
            ? null
            : AppBar(
                title: Text(['Flow', 'Activity', 'Plan', 'My profile'][_tab]),
                actions: [
                  IconButton(
                    onPressed: _busy ? null : _signOut,
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
        bottomNavigationBar: FlowBottomNav(
          selectedIndex: _tab,
          onSelected: _busy ? null : (value) => setState(() => _tab = value),
        ),
        floatingActionButtonLocation: const FlowFabLocation(),
        floatingActionButton: FlowActions(
          onAdvisor: _busy || _advisorOpen ? null : _openAdvisor,
          primary: _tab < 2
              ? FloatingActionButton(
                  heroTag: 'addExpenseFab',
                  onPressed: _busy ? null : _addExpense,
                  tooltip: 'Add expense',
                  child: const Icon(Icons.add),
                )
              : null,
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            TickerMode(
              enabled: _tab == 0,
              child: DashboardScreen(
                userId: widget.user.uid,
                embedded: true,
                categoryLabel: _categoryLabel,
                onExpense: _editExpense,
                displayName: _profile.displayName.isEmpty
                    ? widget.user.displayName
                    : _profile.displayName,
                photoUrl: widget.user.photoURL,
                profile: _profile,
                onProfile: () => setState(() => _tab = 3),
                onCustomize: _profileReady ? _editProfile : null,
                onAdd: _addExpense,
                onBudget: () =>
                    _openPage(MonthlyBudgetScreen(userId: widget.user.uid)),
                onBills: () =>
                    _openPage(PlannedBillsScreen(userId: widget.user.uid)),
                onGoals: () =>
                    _openPage(SavingsGoalsScreen(userId: widget.user.uid)),
                onAdvisor: _openAdvisor,
                onActivity: (month) => setState(() {
                  _tab = 1;
                  _searchController.clear();
                  _searchQuery = '';
                  _filterCategoryId = null;
                  _filterDateRange = DateTimeRange(
                    start: month,
                    end: DateTime(month.year, month.month + 1, 0),
                  );
                }),
              ),
            ),
            TickerMode(enabled: _tab == 1, child: _buildActivity()),
            TickerMode(enabled: _tab == 2, child: _buildPlan()),
            _buildMore(),
          ],
        ),
      ),
    );
  }

  void _showActivityFilters() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Transaction dates',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('Today'),
              onTap: () {
                Navigator.pop(sheet);
                _filterToday();
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('This month'),
              onTap: () {
                Navigator.pop(sheet);
                _filterThisMonth();
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: const Text('Choose dates'),
              onTap: () {
                Navigator.pop(sheet);
                _pickDateRange();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('All dates'),
              onTap: () {
                Navigator.pop(sheet);
                setState(() => _filterDateRange = null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.filter_alt_off_outlined),
              title: const Text('Clear all filters'),
              onTap: () {
                Navigator.pop(sheet);
                _clearFilters();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivity() => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: StreamBuilder<List<Expense>>(
          stream: _expensesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Could not load expenses. Please try again later.',
                  ),
                ),
              );
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final range = _filterDateRange;
            final sameMonth =
                range != null &&
                range.start.year == range.end.year &&
                range.start.month == range.end.month &&
                range.start.day == 1 &&
                range.end.day ==
                    DateTime(range.start.year, range.start.month + 1, 0).day;
            final label = range == null
                ? 'All recorded spending'
                : sameMonth
                ? '${FlowFormat.month(range.start)} spending'
                : 'Selected spending';
            final categories = _categoriesById.values.toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
            return FlowActivityView(
              expenses: _filterExpenses(snapshot.data!),
              categories: categories,
              selectedCategory: _filterCategoryId,
              periodLabel: label,
              dateFilterLabel: range == null
                  ? 'All dates'
                  : '${FlowFormat.shortDate(range.start)} – ${FlowFormat.shortDate(range.end)}',
              searchController: _searchController,
              onSearch: (value) => setState(() => _searchQuery = value),
              onCategory: (value) => setState(() => _filterCategoryId = value),
              onFilters: _showActivityFilters,
              onClear: _clearFilters,
              onEdit: _editExpense,
              onDelete: _deleteExpense,
              categoryLabel: _categoryLabel,
              busy: _busy,
              now: DateTime.now(),
            );
          },
        ),
      ),
    ),
  );

  void _leavePlanning(int tab) {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    setState(() => _tab = tab);
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _destination(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback open,
  ) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: open,
    ),
  );

  Widget _buildPlan() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
        children: [
          const FlowLiquidCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make room for what matters.',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12),
                Text('Budgets, bills and savings. One clear plan.'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _destination(
            'Budgets',
            'Set limits and see what is left',
            Icons.account_balance_wallet_outlined,
            const Color(0xFF075BEE),
            () => _openPage(
              MonthlyBudgetScreen(
                userId: widget.user.uid,
                onOpenAdvisor: _openAdvisor,
                onNavigate: _leavePlanning,
              ),
            ),
          ),
          _destination(
            'Bills',
            'Upcoming payments and payment history',
            Icons.receipt_long_outlined,
            const Color(0xFF008D83),
            () => _openPage(
              PlannedBillsScreen(
                userId: widget.user.uid,
                onOpenAdvisor: _openAdvisor,
                onNavigate: _leavePlanning,
              ),
            ),
          ),
          _destination(
            'Savings goals',
            'Build towards your next milestone',
            Icons.flag_outlined,
            const Color(0xFF8949DE),
            () => _openPage(
              SavingsGoalsScreen(
                userId: widget.user.uid,
                onOpenAdvisor: _openAdvisor,
                onNavigate: _leavePlanning,
              ),
            ),
          ),
          _destination(
            'Purchase simulator',
            'Explore a purchase before you spend',
            Icons.shopping_bag_outlined,
            const Color(0xFFE87500),
            () => _openPage(PurchaseSimulatorScreen(userId: widget.user.uid)),
          ),
        ],
      ),
    ),
  );

  Future<void> _editProfile() async {
    if (!_profileReady || _busy) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(user: widget.user, profile: _profile),
      ),
    );
    if (mounted && saved == true)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile and home preferences saved.')),
      );
  }

  Widget _buildMore() => ProfileScreen(
    user: widget.user,
    profile: _profile,
    loadError:
        _profileError ?? (_profileReady ? null : 'Loading your profile…'),
    onEdit: _profileReady && !_busy ? _editProfile : null,
    onCategories: () =>
        _openPage(CategoryManagerScreen(userId: widget.user.uid)),
    onAdvisor: _openAdvisor,
    onSignOut: () {
      if (!_busy) _signOut();
    },
  );
}
