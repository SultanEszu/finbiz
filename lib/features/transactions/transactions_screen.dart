import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/data/models/finance_models.dart';
import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(financeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => const AddTransactionSheet(),
        ),
        child: const Icon(Icons.add),
      ),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          onRetry: () => ref.read(financeRepositoryProvider.notifier).refresh(),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () =>
              ref.read(financeRepositoryProvider.notifier).refresh(),
          child: state.transactions.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 180),
                    Center(
                      child: Text(
                        'Belum ada transaksi. Tambahkan transaksi pertama Anda.',
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = state.transactions[index];
                    final category = state.categories
                        .where((item) => item.id == transaction.categoryId)
                        .toList();
                    final amount = NumberFormat.currency(
                      symbol: 'Rp ',
                      locale: 'id_ID',
                      decimalDigits: 0,
                    ).format(transaction.amount);

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
                                  (transaction.type == TransactionType.income
                                          ? AppTheme.success
                                          : AppTheme.error)
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              transaction.type == TransactionType.income
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: transaction.type == TransactionType.income
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  transaction.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  category.isEmpty
                                      ? 'Kategori dihapus'
                                      : category.first.name,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat(
                                    'dd MMM yyyy',
                                    'id_ID',
                                  ).format(transaction.date),
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${transaction.type == TransactionType.income ? '+' : '-'} $amount',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      transaction.type == TransactionType.income
                                      ? AppTheme.success
                                      : AppTheme.error,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                transaction.description.isEmpty
                                    ? 'Tanpa catatan'
                                    : transaction.description,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                _showEditor(context, transaction);
                              } else {
                                _confirmDelete(context, ref, transaction);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Ubah')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Hapus'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _showEditor(BuildContext context, FinanceTransaction transaction) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddTransactionSheet(initialTransaction: transaction),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    FinanceTransaction transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: const Text('Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(financeRepositoryProvider.notifier)
          .deleteTransaction(transaction.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(financeErrorMessage(error))));
      }
    }
  }
}

class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({
    this.initialType = TransactionType.expense,
    this.initialTransaction,
    super.key,
  });

  final TransactionType initialType;
  final FinanceTransaction? initialTransaction;

  @override
  ConsumerState<AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  late TransactionType _type;
  String? _categoryId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final transaction = widget.initialTransaction;
    _type = transaction?.type ?? widget.initialType;
    _titleController.text = transaction?.title ?? '';
    _amountController.text = transaction?.amount.toString() ?? '';
    _descriptionController.text = transaction?.description ?? '';
    _categoryId = transaction?.categoryId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final financeAsync = ref.watch(financeRepositoryProvider);
    final categories = financeAsync.when(
      data: (state) => state.categories
          .where((item) => item.isExpense == (_type == TransactionType.expense))
          .toList(),
      loading: () => <FinanceCategory>[],
      error: (error, stackTrace) => <FinanceCategory>[],
    );
    final categoryExists = categories.any((item) => item.id == _categoryId);
    final selectedCategoryId = categoryExists
        ? _categoryId
        : categories.isEmpty
        ? null
        : categories.first.id;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.initialTransaction == null
                      ? 'Tambah transaksi'
                      : 'Ubah transaksi',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TransactionType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Jenis transaksi'),
              items: TransactionType.values
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(transactionTypeLabel(item)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _type = value;
                    _categoryId = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Judul'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Jumlah'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCategoryId,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: categories
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Deskripsi'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(
                  _isSaving
                      ? 'Menyimpan...'
                      : widget.initialTransaction == null
                      ? 'Simpan transaksi'
                      : 'Simpan perubahan',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    if (_titleController.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi judul dan jumlah yang valid.')),
      );
      return;
    }

    final state = ref.read(financeRepositoryProvider).value;
    final matchingCategories = state?.categories
        .where((item) => item.isExpense == (_type == TransactionType.expense))
        .toList();
    if (matchingCategories == null || matchingCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tambahkan kategori yang sesuai terlebih dahulu.'),
        ),
      );
      return;
    }
    final categoryId = matchingCategories.any((item) => item.id == _categoryId)
        ? _categoryId!
        : matchingCategories.first.id;

    final transaction = FinanceTransaction(
      id: const Uuid().v4(),
      title: _titleController.text.trim(),
      categoryId: categoryId,
      amount: amount,
      date: DateTime.now(),
      type: _type,
      description: _descriptionController.text.trim(),
    );
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(financeRepositoryProvider.notifier);
      if (widget.initialTransaction == null) {
        await repository.addTransaction(transaction);
      } else {
        await repository.updateTransaction(transaction);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialTransaction == null
                ? 'Transaksi berhasil disimpan.'
                : 'Perubahan transaksi berhasil disimpan.',
          ),
        ),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Transaksi gagal dimuat. Periksa koneksi lalu coba lagi.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}
