<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Support\FinBizProvisioner;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8'],
            'full_name' => ['required', 'string', 'max:255'],
        ]);
        $data['email'] = mb_strtolower(trim($data['email']));

        if ($data['email'] === 'adminfinbiz@gmail.com') {
            throw ValidationException::withMessages([
                'email' => 'Akun Creator harus dibuat oleh administrator.',
            ]);
        }

        [$user, $token] = DB::transaction(function () use ($data) {
            $user = User::create([
                'id' => (string) Str::uuid(),
                'full_name' => trim($data['full_name']),
                'email' => $data['email'],
                'password' => Hash::make($data['password']),
                'role' => 'user',
            ]);
            FinBizProvisioner::createBusiness($user);

            return [$user, $user->createToken('finbiz-app')->plainTextToken];
        });

        return response()->json([
            'token' => $token,
            'user' => $this->userPayload($user),
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);
        $credentials['email'] = mb_strtolower(trim($credentials['email']));

        $user = User::query()->where('email', $credentials['email'])->first();
        if ($user === null || ! Hash::check($credentials['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => 'Email atau kata sandi tidak sesuai.',
            ]);
        }

        if ($user->email_verified_at === null && config('auth.require_email_verification')) {
            throw ValidationException::withMessages([
                'email' => 'Konfirmasi email Anda sebelum masuk.',
            ]);
        }

        return response()->json([
            'token' => $user->createToken('finbiz-app')->plainTextToken,
            'user' => $this->userPayload($user),
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json(['user' => $this->userPayload($request->user())]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()?->delete();

        return response()->json(['success' => true]);
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        $data = $request->validate(['email' => ['required', 'email']]);
        $status = Password::sendResetLink([
            'email' => mb_strtolower(trim($data['email'])),
        ]);

        if ($status === Password::RESET_LINK_SENT ||
            $status === Password::INVALID_USER) {
            return response()->json(['message' => 'Jika email terdaftar, tautan pengaturan ulang akan dikirim.']);
        }

        if ($status === Password::RESET_THROTTLED) {
            return response()->json([
                'message' => 'Terlalu banyak permintaan. Coba lagi beberapa saat.',
            ], 429);
        }

        return response()->json(['message' => 'Tautan pengaturan ulang tidak dapat dikirim. Hubungi pengelola aplikasi.'], 500);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string'],
            'email' => ['required', 'email'],
            'password' => ['required', 'string', 'min:8'],
        ]);

        $status = Password::reset(
            [
                'email' => mb_strtolower(trim($data['email'])),
                'password' => $data['password'],
                'password_confirmation' => $data['password'],
                'token' => $data['token'],
            ],
            function (User $user, string $password) {
                $user->forceFill([
                    'password' => Hash::make($password),
                    'must_change_password' => false,
                ])->save();
                $user->tokens()->delete();
                event(new PasswordReset($user));
            },
        );

        if ($status !== Password::PASSWORD_RESET) {
            return response()->json(['message' => 'Tautan pengaturan ulang tidak valid atau sudah kedaluwarsa.'], 422);
        }

        return response()->json(['message' => 'Kata sandi berhasil diperbarui.']);
    }

    public function changePassword(Request $request): JsonResponse
    {
        $data = $request->validate(['password' => ['required', 'string', 'min:8']]);
        $user = $request->user();
        $user->forceFill([
            'password' => Hash::make($data['password']),
            'must_change_password' => false,
        ])->save();

        return response()->json(['user' => $this->userPayload($user->refresh())]);
    }

    public static function userPayload(User $user): array
    {
        return [
            'id' => (string) $user->id,
            'email' => $user->email,
            'full_name' => $user->full_name,
            'role' => $user->role,
            'avatar_url' => $user->avatar_url,
            'must_change_password' => (bool) $user->must_change_password,
        ];
    }
}
