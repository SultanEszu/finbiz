<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('businesses', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_id')->unique()->constrained('users')->cascadeOnDelete();
            $table->string('business_name');
            $table->text('description')->default('');
            $table->timestamps();
        });

        Schema::create('business_settings', function (Blueprint $table) {
            $table->foreignUuid('business_id')->primary()->constrained()->cascadeOnDelete();
            $table->char('currency_code', 3)->default('IDR');
            $table->string('time_zone')->default('Asia/Jakarta');
            $table->unsignedTinyInteger('fiscal_start_month')->default(1);
            $table->json('preferences');
            $table->timestamps();
        });

        Schema::create('cash_accounts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('business_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('account_type')->default('cash');
            $table->decimal('opening_balance', 18, 2)->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['business_id', 'name']);
        });

        Schema::create('account_transfers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('business_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('from_cash_account_id')->constrained('cash_accounts');
            $table->foreignUuid('to_cash_account_id')->constrained('cash_accounts');
            $table->decimal('amount', 18, 2);
            $table->string('status')->default('posted');
            $table->dateTime('transfer_date');
            $table->text('description')->default('');
            $table->timestamps();
        });

        Schema::create('categories', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('business_id')->nullable()->constrained()->cascadeOnDelete();
            $table->boolean('is_global')->default(false);
            $table->string('name');
            $table->string('type');
            $table->string('icon_name')->default('category');
            $table->unsignedBigInteger('color_value')->default(4284513675);
            $table->timestamps();
            $table->index(['business_id', 'type']);
        });

        Schema::create('transactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('business_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignUuid('category_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignUuid('cash_account_id')->nullable()->constrained()->nullOnDelete();
            $table->string('transaction_type');
            $table->string('title')->default('');
            $table->decimal('amount', 18, 2);
            $table->text('description')->default('');
            $table->date('transaction_date');
            $table->string('status')->default('posted');
            $table->timestamps();
            $table->index(['user_id', 'transaction_date']);
            $table->index(['business_id', 'transaction_date']);
        });

        Schema::create('budgets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('business_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignUuid('category_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('amount', 18, 2);
            $table->string('period');
            $table->date('start_date');
            $table->date('end_date');
            $table->timestamps();
            $table->index(['user_id', 'start_date', 'end_date']);
        });

        Schema::create('savings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('business_id')->nullable()->constrained()->cascadeOnDelete();
            $table->string('target_name');
            $table->decimal('target_amount', 18, 2);
            $table->decimal('current_amount', 18, 2)->default(0);
            $table->date('target_date')->nullable();
            $table->string('status')->default('active');
            $table->timestamps();
            $table->index(['user_id', 'created_at']);
        });

        Schema::create('debts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('business_id')->nullable()->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('contact')->default('');
            $table->decimal('amount', 18, 2);
            $table->date('due_date');
            $table->string('type');
            $table->text('description')->default('');
            $table->timestamps();
            $table->index(['user_id', 'due_date']);
        });

        Schema::create('debt_payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('business_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('debt_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('cash_account_id')->constrained();
            $table->decimal('principal_amount', 18, 2)->default(0);
            $table->decimal('interest_amount', 18, 2)->default(0);
            $table->decimal('fee_amount', 18, 2)->default(0);
            $table->dateTime('payment_date');
            $table->string('status')->default('posted');
            $table->text('description')->default('');
            $table->timestamps();
        });

        Schema::create('notifications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('business_id')->nullable()->constrained()->cascadeOnDelete();
            $table->string('title');
            $table->text('message')->default('');
            $table->boolean('is_read')->default(false);
            $table->timestamps();
            $table->index(['user_id', 'created_at']);
        });

        Schema::create('audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action');
            $table->foreignUuid('target_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->json('details');
            $table->timestamps();
        });

        Schema::create('transaction_attachments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('business_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('transaction_id')->constrained()->cascadeOnDelete();
            $table->string('storage_path')->unique();
            $table->string('original_name');
            $table->string('content_type');
            $table->unsignedBigInteger('byte_size');
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transaction_attachments');
        Schema::dropIfExists('audit_logs');
        Schema::dropIfExists('notifications');
        Schema::dropIfExists('debt_payments');
        Schema::dropIfExists('debts');
        Schema::dropIfExists('savings');
        Schema::dropIfExists('budgets');
        Schema::dropIfExists('transactions');
        Schema::dropIfExists('categories');
        Schema::dropIfExists('account_transfers');
        Schema::dropIfExists('cash_accounts');
        Schema::dropIfExists('business_settings');
        Schema::dropIfExists('businesses');
    }
};
