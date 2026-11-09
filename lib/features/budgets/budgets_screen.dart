import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(financeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Anggaran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => const _AddBudgetSheet(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Buat anggaran'),
      ),
      body: budgetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Anggaran gagal dimuat.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.read(financeRepositoryProvider.notifier).refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () =>
              ref.read(financeRepositoryProvider.notifier).refresh(),
          child: state.budgets.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 180),
                    Center(
                      child: Text(
                        'Belum ada anggaran. Buat anggaran pertama Anda.',
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.budgets.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final budget = state.budgets[index];
                    return Card(
                      child: ListTile(
                        title: Text('Anggaran ${_periodLabel(budget.period)}'),
                        subtitle: Text(
                          '${DateFormat('dd MMM yyyy', 'id_ID').format(budget.startDate)}'
                          ' – ${DateFormat('dd MMM yyyy', 'id_ID').format(budget.endDate)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_currency(budget.amount)),
                            IconButton(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(financeRepositoryProvider.notifier)
                                      .deleteBudget(budget.id);
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          financeErrorMessage(error),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _AddBudgetSheet extends ConsumerStatefulWidget {
  const _AddBudgetSheet();

  @override
  ConsumerState<_AddBudgetSheet> createState() => _AddBudgetSheetState();
}

class _AddBudgetSheetState extends ConsumerState<_AddBudgetSheet> {
  final _amount = TextEditingController();
  String _period = 'monthly';
  bool _isSaving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Batas anggaran'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _period,
            decoration: const InputDecoration(labelText: 'Periode'),
            items: const [
              DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
              DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
              DropdownMenuItem(value: 'yearly', child: Text('Tahunan')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _period = value);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              child: Text(_isSaving ? 'Menyimpan...' : 'Simpan anggaran'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan batas anggaran yang valid.')),
      );
      return;
    }

    final now = DateTime.now();
    late final DateTime start;
    late final DateTime end;
    switch (_period) {
      case 'weekly':
        final today = DateTime(now.year, now.month, now.day);
        start = today.subtract(Duration(days: today.weekday - 1));
        end = start.add(const Duration(days: 6));
      case 'monthly':
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
      case 'yearly':
        start = DateTime(now.year);
        end = DateTime(now.year, 12, 31);
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(financeRepositoryProvider.notifier)
          .addBudget(
            amount: amount,
            period: _period,
            startDate: start,
            endDate: end,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(financeErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

String _periodLabel(String period) => switch (period) {
  'weekly' => 'mingguan',
  'yearly' => 'tahunan',
  _ => 'bulanan',
};

String _currency(double value) => NumberFormat.currency(
  symbol: 'Rp ',
  locale: 'id_ID',
  decimalDigits: 0,
).format(value);
