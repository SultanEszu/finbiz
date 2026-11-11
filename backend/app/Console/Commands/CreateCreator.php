<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Support\FinBizProvisioner;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class CreateCreator extends Command
{
    protected $signature = 'finbiz:create-creator';

    protected $description = 'Create the initial FinBiz Creator account securely.';

    public function handle(): int
    {
        $email = 'adminfinbiz@gmail.com';
        if (User::query()->where('email', $email)->exists()) {
            $this->error('Creator account already exists; no account was changed.');

            return self::FAILURE;
        }

        $fullName = trim((string) $this->ask('Nama Creator'));
        if ($fullName === '') {
            $this->error('Nama Creator wajib diisi.');

            return self::FAILURE;
        }
        $password = $this->secret('Password (minimal 8 karakter)');
        $confirmation = $this->secret('Ulangi password');
        if (! is_string($password) || strlen($password) < 8 || $password !== $confirmation) {
            $this->error('Password harus minimal 8 karakter dan kedua input harus sama.');

            return self::FAILURE;
        }

        DB::transaction(function () use ($email, $fullName, $password) {
            $user = User::create([
                'id' => (string) Str::uuid(),
                'email' => $email,
                'full_name' => $fullName,
                'password' => Hash::make($password),
                'role' => 'creator',
                'email_verified_at' => now(),
            ]);
            FinBizProvisioner::createBusiness($user);
        });

        $this->info('Creator berhasil dibuat. Password tidak ditampilkan atau disimpan ke source code.');

        return self::SUCCESS;
    }
}
