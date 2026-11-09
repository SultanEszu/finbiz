import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/data/models/finance_models.dart';
import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref
        .watch(financeRepositoryProvider)
        .when(
          data: (state) => state.debts,
          loading: () => FinanceState.initialState().debts,
          error: (error, stackTrace) => FinanceState.initialState().debts,
        );
    final repository = ref.read(financeRepositoryProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Hutang & Piutang')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDebtSheet(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _DebtStatCard(
                    label: 'Piutang',
                    amount: repository.receivableTotal,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DebtStatCard(
                    label: 'Hutang',
                    amount: repository.payableTotal,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: debts.length,
                itemBuilder: (context, index) {
                  final debt = debts[index];
                  final amount = NumberFormat.currency(
                    symbol: 'Rp ',
                    locale: 'id_ID',
                    decimalDigits: 0,
                  ).format(debt.amount);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color:
                                (debt.type == DebtType.receivable
                                        ? AppTheme.success
                                        : AppTheme.error)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            debt.type == DebtType.receivable
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            color: debt.type == DebtType.receivable
                                ? AppTheme.success
                                : AppTheme.error,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                debt.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                debt.contact,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat(
                                  'dd MMM yyyy',
                                  'id_ID',
                                ).format(debt.dueDate),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${debtTypeLabel(debt.type)}\n$amount',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: debt.type == DebtType.receivable
                                    ? AppTheme.success
                                    : AppTheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDebtSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _AddDebtSheet(ref: ref),
    );
  }
}

class _DebtStatCard extends StatelessWidget {
  const _DebtStatCard({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      symbol: 'Rp ',
      locale: 'id_ID',
      decimalDigits: 0,
    ).format(amount);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Text(
            currency,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddDebtSheet extends ConsumerStatefulWidget {
  const _AddDebtSheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends ConsumerState<_AddDebtSheet> {
  final nameController = TextEditingController();
  final contactController = TextEditingController();
  final amountController = TextEditingController();
  DebtType type = DebtType.payable;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Tambah catatan hutang',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Nama'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contactController,
            decoration: const InputDecoration(labelText: 'Kontak'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DebtType>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Jenis'),
            items: DebtType.values.map((option) {
              return DropdownMenuItem(
                value: option,
                child: Text(debtTypeLabel(option)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => type = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Jumlah'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isSaving ? 'Menyimpan...' : 'Simpan catatan'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final name = nameController.text.trim();
    final amountText = amountController.text.trim();
    final amount = double.tryParse(amountText) ?? 0;

    if (name.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap masukkan nama dan jumlah yang valid.'),
        ),
      );
      return;
    }

    final debt = DebtEntry(
      id: const Uuid().v4(),
      name: name,
      contact: contactController.text.trim(),
      amount: amount,
      dueDate: DateTime.now().add(const Duration(days: 14)),
      type: type,
      description: 'Dicatat di FinBiz',
    );

    setState(() => _isSaving = true);
    try {
      await ref.read(financeRepositoryProvider.notifier).addDebt(debt);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan berhasil disimpan.')),
      );
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
