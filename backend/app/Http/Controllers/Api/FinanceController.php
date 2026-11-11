<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Support\FinBizProvisioner;
use Illuminate\Database\Query\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class FinanceController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $businessIds = DB::table('businesses')
            ->where('owner_id', $user->id)
            ->pluck('id');

        $categories = DB::table('categories')
            ->when($user->role === 'user', function (Builder $query) use ($user, $businessIds) {
                $query->where(function (Builder $scope) use ($user, $businessIds) {
                    $scope->where('user_id', $user->id)
                        ->orWhere(function (Builder $global) {
                            $global->whereNull('user_id')->whereNull('business_id');
                        })
                        ->orWhereIn('business_id', $businessIds);
                });
            })
            ->orderBy('name')
            ->get(['id', 'name', 'type', 'icon_name', 'color_value']);

        $transactions = $this->visibleRecords('transactions', $user)
            ->where('status', 'posted')
            ->orderByDesc('transaction_date')
            ->get([
                'id', 'title', 'category_id', 'amount', 'transaction_date',
                'transaction_type', 'description',
            ])
            ->map(fn ($row) => array_merge((array) $row, ['amount' => (float) $row->amount]));
        $debts = $this->visibleRecords('debts', $user)
            ->orderBy('due_date')
            ->get(['id', 'name', 'contact', 'amount', 'due_date', 'type', 'description'])
            ->map(fn ($row) => array_merge((array) $row, ['amount' => (float) $row->amount]));
        $budgets = $this->visibleRecords('budgets', $user)
            ->orderBy('end_date')
            ->get(['id', 'amount', 'period', 'start_date', 'end_date'])
            ->map(fn ($row) => array_merge((array) $row, ['amount' => (float) $row->amount]));
        $notifications = $this->visibleRecords('notifications', $user)
            ->orderByDesc('created_at')
            ->limit(5)
            ->get(['id', 'title', 'message', 'is_read', 'created_at'])
            ->map(fn ($row) => array_merge((array) $row, ['is_read' => (bool) $row->is_read]));
        $savings = $this->visibleRecords('savings', $user)
            ->orderByDesc('created_at')
            ->get(['id', 'target_name', 'target_amount', 'current_amount', 'target_date'])
            ->map(fn ($row) => array_merge((array) $row, [
                'target_amount' => (float) $row->target_amount,
                'current_amount' => (float) $row->current_amount,
            ]));

        $accounts = DB::table('cash_accounts')
            ->join('businesses', 'businesses.id', '=', 'cash_accounts.business_id')
            ->when($user->role === 'user', fn (Builder $query) => $query->where('businesses.owner_id', $user->id))
            ->where('cash_accounts.is_active', true)
            ->orderBy('cash_accounts.created_at')
            ->orderBy('cash_accounts.id')
            ->get(['cash_accounts.id', 'cash_accounts.opening_balance']);
        $accountIds = $accounts->pluck('id');
        $transactionBalances = DB::table('transactions')
            ->whereIn('cash_account_id', $accountIds)
            ->where('status', 'posted')
            ->selectRaw(
                "cash_account_id, COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount WHEN transaction_type = 'expense' THEN -amount ELSE 0 END), 0) as balance",
            )
            ->groupBy('cash_account_id')
            ->pluck('balance', 'cash_account_id');
        $outgoingTransfers = DB::table('account_transfers')
            ->whereIn('from_cash_account_id', $accountIds)
            ->where('status', 'posted')
            ->selectRaw('from_cash_account_id, COALESCE(SUM(amount), 0) as amount')
            ->groupBy('from_cash_account_id')
            ->pluck('amount', 'from_cash_account_id');
        $incomingTransfers = DB::table('account_transfers')
            ->whereIn('to_cash_account_id', $accountIds)
            ->where('status', 'posted')
            ->selectRaw('to_cash_account_id, COALESCE(SUM(amount), 0) as amount')
            ->groupBy('to_cash_account_id')
            ->pluck('amount', 'to_cash_account_id');
        $debtPaymentBalances = DB::table('debt_payments')
            ->join('debts', 'debts.id', '=', 'debt_payments.debt_id')
            ->whereIn('debt_payments.cash_account_id', $accountIds)
            ->where('debt_payments.status', 'posted')
            ->selectRaw(
                "debt_payments.cash_account_id, COALESCE(SUM(CASE WHEN debts.type = 'payable' THEN -(principal_amount + interest_amount + fee_amount) ELSE principal_amount + interest_amount + fee_amount END), 0) as balance",
            )
            ->groupBy('debt_payments.cash_account_id')
            ->pluck('balance', 'debt_payments.cash_account_id');
        $balances = $accounts->map(fn ($account) => [
            'balance' => (float) $account->opening_balance +
                (float) ($transactionBalances[$account->id] ?? 0) -
                (float) ($outgoingTransfers[$account->id] ?? 0) +
                (float) ($incomingTransfers[$account->id] ?? 0) +
                (float) ($debtPaymentBalances[$account->id] ?? 0),
        ]);

        return response()->json([
            'categories' => $categories,
            'transactions' => $transactions,
            'cash_account_balances' => $balances,
            'debts' => $debts,
            'budgets' => $budgets,
            'notifications' => $notifications,
            'savings' => $savings,
        ]);
    }

    public function storeTransaction(Request $request): JsonResponse
    {
        $data = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'category_id' => ['nullable', 'uuid', 'exists:categories,id'],
            'amount' => ['required', 'numeric', 'gt:0'],
            'transaction_date' => ['required', 'date'],
            'transaction_type' => ['required', 'in:income,expense'],
            'description' => ['nullable', 'string'],
        ]);
        $user = $request->user();
        $businessId = FinBizProvisioner::businessIdFor($user);
        $this->assertCategoryInBusiness($data['category_id'] ?? null, $businessId);
        $data['description'] = $data['description'] ?? '';
        $this->insertOwnedRecord('transactions', $user, $data + ['status' => 'posted']);

        return response()->json(['success' => true], 201);
    }

    public function updateTransaction(Request $request, string $transaction): JsonResponse
    {
        $data = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'category_id' => ['nullable', 'uuid', 'exists:categories,id'],
            'amount' => ['required', 'numeric', 'gt:0'],
            'transaction_date' => ['required', 'date'],
            'transaction_type' => ['required', 'in:income,expense'],
            'description' => ['nullable', 'string'],
        ]);
        $query = $this->visibleRecords('transactions', $request->user())
            ->where('id', $transaction);
        abort_unless($query->exists(), 404);
        $existing = $query->first(['business_id']);
        $this->assertCategoryInBusiness(
            $data['category_id'] ?? null,
            $existing->business_id,
        );
        $data['description'] = $data['description'] ?? '';
        $query->update($data + ['updated_at' => now()]);

        return response()->json(['success' => true]);
    }

    public function deleteTransaction(Request $request, string $transaction): JsonResponse
    {
        $query = $this->visibleRecords('transactions', $request->user())
            ->where('id', $transaction);
        abort_unless($query->exists(), 404);
        $query->update(['status' => 'voided', 'updated_at' => now()]);

        return response()->json(['success' => true]);
    }

    public function storeCategory(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'type' => ['required', 'in:income,expense'],
            'icon_name' => ['required', 'string', 'max:100'],
            'color_value' => ['required', 'integer', 'min:0'],
        ]);
        $this->insertOwnedRecord('categories', $request->user(), $data);

        return response()->json(['success' => true], 201);
    }

    public function deleteCategory(Request $request, string $category): JsonResponse
    {
        $query = $this->visibleRecords('categories', $request->user())
            ->where('id', $category);
        abort_unless($query->exists(), 404);
        $query->delete();

        return response()->json(['success' => true]);
    }

    public function storeDebt(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'contact' => ['nullable', 'string', 'max:255'],
            'amount' => ['required', 'numeric', 'gt:0'],
            'due_date' => ['required', 'date'],
            'type' => ['required', 'in:payable,receivable'],
            'description' => ['nullable', 'string'],
        ]);
        $data['description'] = $data['description'] ?? '';
        $data['contact'] = $data['contact'] ?? '';
        $this->insertOwnedRecord('debts', $request->user(), $data);

        return response()->json(['success' => true], 201);
    }

    public function storeSavings(Request $request): JsonResponse
    {
        $data = $request->validate([
            'target_name' => ['required', 'string', 'max:255'],
            'target_amount' => ['required', 'numeric', 'gt:0'],
            'target_date' => ['nullable', 'date'],
        ]);
        $this->insertOwnedRecord('savings', $request->user(), $data + [
            'current_amount' => 0,
            'status' => 'active',
        ]);

        return response()->json(['success' => true], 201);
    }

    public function contributeSavings(Request $request, string $saving): JsonResponse
    {
        $data = $request->validate(['amount' => ['required', 'numeric', 'gt:0']]);

        DB::transaction(function () use ($request, $saving, $data) {
            $query = $this->visibleRecords('savings', $request->user())
                ->where('id', $saving);
            $target = $query->lockForUpdate()->first();
            abort_if($target === null, 404);
            $newAmount = (float) $target->current_amount + (float) $data['amount'];
            abort_if($newAmount > (float) $target->target_amount, 422, 'Jumlah setoran melebihi target.');
            $query->update(['current_amount' => $newAmount, 'updated_at' => now()]);
        });

        return response()->json(['success' => true]);
    }

    public function deleteSavings(Request $request, string $saving): JsonResponse
    {
        $query = $this->visibleRecords('savings', $request->user())->where('id', $saving);
        abort_unless($query->exists(), 404);
        $query->delete();

        return response()->json(['success' => true]);
    }

    public function storeBudget(Request $request): JsonResponse
    {
        $data = $request->validate([
            'amount' => ['required', 'numeric', 'gt:0'],
            'period' => ['required', 'in:weekly,monthly,yearly'],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date', 'after_or_equal:start_date'],
        ]);
        $this->insertOwnedRecord('budgets', $request->user(), $data);

        return response()->json(['success' => true], 201);
    }

    public function deleteBudget(Request $request, string $budget): JsonResponse
    {
        $query = $this->visibleRecords('budgets', $request->user())->where('id', $budget);
        abort_unless($query->exists(), 404);
        $query->delete();

        return response()->json(['success' => true]);
    }

    private function visibleRecords(string $table, User $user): Builder
    {
        $query = DB::table($table);
        if ($user->role === 'user') {
            $query->where('user_id', $user->id);
        }

        return $query;
    }

    private function insertOwnedRecord(string $table, User $user, array $data): void
    {
        DB::transaction(function () use ($table, $user, $data) {
            $businessId = FinBizProvisioner::businessIdFor($user);
            $now = now();
            $row = [
                'id' => (string) Str::uuid(),
                'user_id' => $user->id,
                'business_id' => $businessId,
                'created_at' => $now,
                'updated_at' => $now,
            ] + match ($table) {
                'transactions' => [
                    'description' => '',
                    'category_id' => null,
                    'cash_account_id' => DB::table('cash_accounts')
                        ->where('business_id', $businessId)
                        ->value('id'),
                ],
                'categories' => ['icon_name' => 'category', 'color_value' => 4284513675],
                'debts' => ['contact' => '', 'description' => ''],
                'savings' => ['current_amount' => 0, 'target_date' => null, 'status' => 'active'],
                default => [],
            };
            $row = array_merge($row, $data);
            DB::table($table)->insert($row);
        });
    }

    private function assertCategoryInBusiness(?string $categoryId, string $businessId): void
    {
        if ($categoryId === null) {
            return;
        }

        $category = DB::table('categories')->where('id', $categoryId)->first();
        abort_unless(
            $category !== null &&
                ((bool) $category->is_global || $category->business_id === $businessId),
            422,
            'Kategori tidak tersedia untuk bisnis ini.',
        );
    }
}
