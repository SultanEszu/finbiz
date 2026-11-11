import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/api_providers.dart';
import '../services/api_client.dart';
import '../models/finance_models.dart';

class FinanceState {
  const FinanceState({
    required this.categories,
    required this.transactions,
    required this.debts,
    required this.budgets,
    required this.notifications,
    required this.savings,
    this.calculatedBalance,
  });

  factory FinanceState.initialState() {
    return const FinanceState(
      categories: [],
      transactions: [],
      debts: [],
      budgets: [],
      notifications: [],
      savings: [],
    );
  }

  final List<FinanceCategory> categories;
  final List<FinanceTransaction> transactions;
  final List<DebtEntry> debts;
  final List<FinanceBudget> budgets;
  final List<FinanceNotification> notifications;
  final List<SavingsTarget> savings;
  final double? calculatedBalance;

  double get totalBalance =>
      calculatedBalance ??
      transactions.fold<double>(
        0,
        (total, item) => total + _signedAmount(item),
      );

  double monthlyTotal(TransactionType type) {
    final now = DateTime.now();
    return transactions
        .where(
          (item) =>
              item.type == type &&
              item.date.year == now.year &&
              item.date.month == now.month,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  List<({String category, double amount})> get categorySummary {
    final totals = <String, double>{};
    for (final transaction in transactions.where(
      (item) => item.type == TransactionType.expense,
    )) {
      final category = categories.where(
        (item) => item.id == transaction.categoryId,
      );
      final name = category.isEmpty ? 'Lainnya' : category.first.name;
      totals[name] = (totals[name] ?? 0) + transaction.amount;
    }
    return totals.entries
        .map((entry) => (category: entry.key, amount: entry.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }

  List<FinanceTransaction> get recentTransactions {
    return [...transactions]..sort((a, b) => b.date.compareTo(a.date));
  }

  double get receivableTotal => debts
      .where((item) => item.type == DebtType.receivable)
      .fold<double>(0, (sum, item) => sum + item.amount);

  double get payableTotal => debts
      .where((item) => item.type == DebtType.payable)
      .fold<double>(0, (sum, item) => sum + item.amount);

  static double _signedAmount(FinanceTransaction item) {
    return item.type == TransactionType.income ? item.amount : -item.amount;
  }
}

class FinanceRepository extends AsyncNotifier<FinanceState> {
  ApiClient get _client => ApiClient.instance;
  FinanceState get _current => state.value ?? FinanceState.initialState();

  double get monthlyIncome => _current.monthlyTotal(TransactionType.income);
  double get monthlyExpense => _current.monthlyTotal(TransactionType.expense);
  double get totalBalance => _current.totalBalance;
  List<({String category, double amount})> get categorySummary =>
      _current.categorySummary;
  List<FinanceTransaction> get recentTransactions =>
      _current.recentTransactions;
  double get receivableTotal => _current.receivableTotal;
  double get payableTotal => _current.payableTotal;

  @override
  FutureOr<FinanceState> build() {
    ref.watch(authStateProvider);
    return _loadState();
  }

  Future<FinanceState> _loadState() async {
    if (_client.currentUser == null) {
      throw StateError('Sesi pengguna tidak tersedia.');
    }

    final response = await _client.get('/finance');
    final categoryRows = _rows(response, 'categories');
    final transactionRows = _rows(response, 'transactions');
    final balanceRows = _rows(response, 'cash_account_balances');
    final debtRows = _rows(response, 'debts');
    final budgetRows = _rows(response, 'budgets');
    final notificationRows = _rows(response, 'notifications');
    final savingsRows = _rows(response, 'savings');

    return FinanceState(
      categories: categoryRows.map(_categoryFromRow).toList(),
      transactions: transactionRows.map(_transactionFromRow).toList(),
      debts: debtRows.map(_debtFromRow).toList(),
      budgets: budgetRows.map(FinanceBudget.fromJson).toList(),
      notifications: notificationRows
          .map(FinanceNotification.fromJson)
          .toList(),
      savings: savingsRows.map(SavingsTarget.fromJson).toList(),
      calculatedBalance: balanceRows.fold<double>(
        0,
        (total, row) => total + (row['balance'] as num).toDouble(),
      ),
    );
  }

  Future<void> refresh() async {
    await _reload();
  }

  Future<void> addTransaction(FinanceTransaction transaction) async {
    _requireUserId();
    await _client.post(
      '/transactions',
      body: {
        'title': transaction.title,
        'category_id': transaction.categoryId.isEmpty
            ? null
            : transaction.categoryId,
        'amount': transaction.amount,
        'transaction_date': transaction.date.toIso8601String().substring(0, 10),
        'transaction_type': transaction.type.name,
        'description': transaction.description,
      },
    );
    await _reload();
  }

  Future<void> updateTransaction(FinanceTransaction transaction) async {
    await _client.put(
      '/transactions/${transaction.id}',
      body: {
        'title': transaction.title,
        'category_id': transaction.categoryId.isEmpty
            ? null
            : transaction.categoryId,
        'amount': transaction.amount,
        'transaction_date': transaction.date.toIso8601String().substring(0, 10),
        'transaction_type': transaction.type.name,
        'description': transaction.description,
      },
    );
    await _reload();
  }

  Future<void> deleteTransaction(String transactionId) async {
    await _client.delete('/transactions/$transactionId');
    await _reload();
  }

  Future<void> addCategory(FinanceCategory category) async {
    _requireUserId();
    await _client.post(
      '/categories',
      body: {
        'name': category.name,
        'type': category.isExpense ? 'expense' : 'income',
        'icon_name': category.iconName,
        'color_value': category.colorValue,
      },
    );
    await _reload();
  }

  Future<void> deleteCategory(String categoryId) async {
    await _client.delete('/categories/$categoryId');
    await _reload();
  }

  Future<void> addDebt(DebtEntry debt) async {
    _requireUserId();
    await _client.post(
      '/debts',
      body: {
        'name': debt.name,
        'contact': debt.contact,
        'amount': debt.amount,
        'due_date': debt.dueDate.toIso8601String().substring(0, 10),
        'type': debt.type.name,
        'description': debt.description,
      },
    );
    await _reload();
  }

  Future<void> addSavingsTarget({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
  }) async {
    _requireUserId();
    await _client.post(
      '/savings',
      body: {
        'target_name': name.trim(),
        'target_amount': targetAmount,
        'target_date': targetDate?.toIso8601String().substring(0, 10),
      },
    );
    await _reload();
  }

  Future<void> addSavingsContribution(
    SavingsTarget target,
    double amount,
  ) async {
    if (amount <= 0 || target.currentAmount + amount > target.targetAmount) {
      throw ArgumentError('Jumlah setoran tidak valid.');
    }
    await _client.post(
      '/savings/${target.id}/contributions',
      body: {'amount': amount},
    );
    await _reload();
  }

  Future<void> deleteSavingsTarget(String targetId) async {
    await _client.delete('/savings/$targetId');
    await _reload();
  }

  Future<void> addBudget({
    required double amount,
    required String period,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _requireUserId();
    await _client.post(
      '/budgets',
      body: {
        'amount': amount,
        'period': period,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
      },
    );
    await _reload();
  }

  Future<void> deleteBudget(String budgetId) async {
    await _client.delete('/budgets/$budgetId');
    await _reload();
  }

  String _requireUserId() {
    final userId = _client.currentUser?.id;
    if (userId == null) throw StateError('Silakan masuk kembali ke akun Anda.');
    return userId;
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> response, String key) {
    final rows = response[key] as List<dynamic>;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> _reload() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _loadState());
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  FinanceCategory _categoryFromRow(Map<String, dynamic> row) {
    return FinanceCategory(
      id: row['id'] as String,
      name: row['name'] as String,
      iconName: row['icon_name'] as String? ?? 'category',
      colorValue: (row['color_value'] as num?)?.toInt() ?? 0xFF94A3B8,
      isExpense: row['type'] == 'expense',
    );
  }

  FinanceTransaction _transactionFromRow(Map<String, dynamic> row) {
    return FinanceTransaction(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      categoryId: row['category_id'] as String? ?? '',
      amount: (row['amount'] as num).toDouble(),
      date: DateTime.parse(row['transaction_date'] as String),
      type: transactionTypeFromString(row['transaction_type'] as String),
      description: row['description'] as String? ?? '',
    );
  }

  DebtEntry _debtFromRow(Map<String, dynamic> row) {
    return DebtEntry(
      id: row['id'] as String,
      name: row['name'] as String,
      contact: row['contact'] as String? ?? '',
      amount: (row['amount'] as num).toDouble(),
      dueDate: DateTime.parse(row['due_date'] as String),
      type: DebtType.values.firstWhere(
        (type) => type.name == row['type'],
        orElse: () => DebtType.payable,
      ),
      description: row['description'] as String? ?? '',
    );
  }
}

final financeRepositoryProvider =
    AsyncNotifierProvider<FinanceRepository, FinanceState>(
      FinanceRepository.new,
    );

String financeErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 403) {
      return 'Anda tidak memiliki izin untuk operasi ini.';
    }
    if (error.statusCode == 422) {
      return 'Data tidak valid: ${error.message}';
    }
    if (error.statusCode >= 500) {
      return 'Server FinBiz mengalami kendala. Periksa koneksi dan coba lagi.';
    }
  }
  return 'Terjadi kesalahan saat menyimpan data. Coba lagi.';
}
