<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class FinBizApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_provisions_finance_data_and_keeps_businesses_isolated(): void
    {
        $first = $this->postJson('/api/auth/register', [
            'email' => 'owner@example.test',
            'password' => 'correct-horse-battery',
            'full_name' => 'Pemilik Pertama',
        ])->assertCreated()
            ->assertJsonStructure(['token', 'user' => ['id', 'email', 'role']])
            ->json();

        $firstHeaders = ['Authorization' => 'Bearer '.$first['token']];
        $this->getJson('/api/finance', $firstHeaders)
            ->assertOk()
            ->assertJsonCount(5, 'categories');

        $this->postJson('/api/transactions', [
            'title' => 'Biaya operasional',
            'amount' => 125000,
            'transaction_date' => '2026-11-11',
            'transaction_type' => 'expense',
        ], $firstHeaders)->assertCreated();

        $businessId = DB::table('businesses')
            ->where('owner_id', $first['user']['id'])
            ->value('id');
        $cashAccounts = DB::table('cash_accounts')
            ->where('business_id', $businessId)
            ->pluck('id');
        $secondAccountId = (string) Str::uuid();
        DB::table('cash_accounts')->insert([
            'id' => $secondAccountId,
            'business_id' => $businessId,
            'name' => 'Bank',
            'account_type' => 'bank',
            'opening_balance' => 0,
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        DB::table('account_transfers')->insert([
            'id' => (string) Str::uuid(),
            'business_id' => $businessId,
            'from_cash_account_id' => $cashAccounts[0],
            'to_cash_account_id' => $secondAccountId,
            'amount' => 500,
            'status' => 'posted',
            'transfer_date' => now(),
            'description' => '',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $debtId = (string) Str::uuid();
        DB::table('debts')->insert([
            'id' => $debtId,
            'user_id' => $first['user']['id'],
            'business_id' => $businessId,
            'name' => 'Pinjaman',
            'contact' => '',
            'amount' => 100,
            'due_date' => '2026-12-01',
            'type' => 'payable',
            'description' => '',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        DB::table('debt_payments')->insert([
            'id' => (string) Str::uuid(),
            'business_id' => $businessId,
            'debt_id' => $debtId,
            'cash_account_id' => $secondAccountId,
            'principal_amount' => 100,
            'interest_amount' => 0,
            'fee_amount' => 0,
            'payment_date' => now(),
            'status' => 'posted',
            'description' => '',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $finance = $this->getJson('/api/finance', $firstHeaders)
            ->assertOk()
            ->assertJsonCount(1, 'transactions')
            ->json();
        $this->assertEqualsCanonicalizing(
            [-125500, 400],
            array_column($finance['cash_account_balances'], 'balance'),
        );

        $second = $this->postJson('/api/auth/register', [
            'email' => 'other@example.test',
            'password' => 'another-correct-password',
            'full_name' => 'Pemilik Kedua',
        ])->assertCreated()->json();

        $this->getJson('/api/auth/me', [
            'Authorization' => 'Bearer '.$second['token'],
        ])->assertOk()
            ->assertJsonPath('user.id', $second['user']['id']);

        $this->getJson('/api/finance', [
            'Authorization' => 'Bearer '.$second['token'],
        ])->assertOk()
            ->assertJsonCount(0, 'transactions')
            ->assertJsonPath('cash_account_balances.0.balance', 0);
    }

    public function test_public_registration_cannot_create_the_creator_account(): void
    {
        $this->postJson('/api/auth/register', [
            'email' => 'adminfinbiz@gmail.com',
            'password' => 'correct-horse-battery',
            'full_name' => 'Creator',
        ])->assertUnprocessable();
    }

    public function test_forgot_password_does_not_disclose_unknown_email_addresses(): void
    {
        $this->postJson('/api/auth/forgot-password', [
            'email' => 'unknown@example.test',
        ])->assertOk()
            ->assertJsonPath(
                'message',
                'Jika email terdaftar, tautan pengaturan ulang akan dikirim.',
            );
    }
}
