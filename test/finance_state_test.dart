import 'package:finbiz/data/models/finance_models.dart';
import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saldo dihitung dari transaksi aktual dan data awal kosong', () {
    final empty = FinanceState.initialState();
    expect(empty.transactions, isEmpty);
    expect(empty.totalBalance, 0);

    final state = FinanceState(
      categories: const [],
      debts: const [],
      budgets: const [],
      notifications: const [],
      savings: const [],
      transactions: [
        FinanceTransaction(
          id: 'income',
          title: 'Pemasukan',
          categoryId: '',
          amount: 1250000,
          date: DateTime(2026, 11, 1),
          type: TransactionType.income,
          description: '',
        ),
        FinanceTransaction(
          id: 'expense',
          title: 'Pengeluaran',
          categoryId: '',
          amount: 250000,
          date: DateTime(2026, 11, 2),
          type: TransactionType.expense,
          description: '',
        ),
      ],
    );

    expect(state.totalBalance, 1000000);
  });
}
