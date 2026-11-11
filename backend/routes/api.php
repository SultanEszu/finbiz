<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\FinanceController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\ReceiptController;
use Illuminate\Support\Facades\Route;

Route::prefix('auth')->group(function () {
    Route::post('/register', [AuthController::class, 'register'])->middleware('throttle:5,1');
    Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:10,1');
    Route::post('/forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:6,1');
    Route::post('/reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:6,1');

    Route::middleware(['auth.guards.reset', 'auth:sanctum'])->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/logout', [AuthController::class, 'logout']);
        Route::post('/change-password', [AuthController::class, 'changePassword']);
    });
});

Route::middleware(['auth.guards.reset', 'auth:sanctum'])->group(function () {
    Route::get('/profiles', [ProfileController::class, 'index']);
    Route::patch('/profile', [ProfileController::class, 'update']);
    Route::post('/managed-users', [ProfileController::class, 'createManagedUser']);
    Route::put('/profiles/{user}/role', [ProfileController::class, 'updateRole']);
    Route::delete('/managed-users/{user}', [ProfileController::class, 'deleteManagedUser']);

    Route::get('/finance', [FinanceController::class, 'index']);
    Route::post('/transactions', [FinanceController::class, 'storeTransaction']);
    Route::put('/transactions/{transaction}', [FinanceController::class, 'updateTransaction']);
    Route::delete('/transactions/{transaction}', [FinanceController::class, 'deleteTransaction']);
    Route::post('/categories', [FinanceController::class, 'storeCategory']);
    Route::delete('/categories/{category}', [FinanceController::class, 'deleteCategory']);
    Route::post('/debts', [FinanceController::class, 'storeDebt']);
    Route::post('/savings', [FinanceController::class, 'storeSavings']);
    Route::post('/savings/{saving}/contributions', [FinanceController::class, 'contributeSavings']);
    Route::delete('/savings/{saving}', [FinanceController::class, 'deleteSavings']);
    Route::post('/budgets', [FinanceController::class, 'storeBudget']);
    Route::delete('/budgets/{budget}', [FinanceController::class, 'deleteBudget']);

    Route::post('/receipts', [ReceiptController::class, 'upload']);
    Route::get('/receipts/signed-url', [ReceiptController::class, 'signedUrl']);
    Route::delete('/receipts', [ReceiptController::class, 'delete']);
});

Route::get('/receipts/{attachment}', [ReceiptController::class, 'download'])
    ->middleware('signed')
    ->name('receipts.download');
