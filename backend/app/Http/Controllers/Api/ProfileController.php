<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Support\FinBizProvisioner;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class ProfileController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        abort_unless(in_array($request->user()->role, ['admin', 'creator'], true), 403);

        return response()->json([
            'users' => User::query()->orderBy('full_name')->get()
                ->map(fn (User $user) => AuthController::userPayload($user)),
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate(['full_name' => ['required', 'string', 'max:255']]);
        $user = $request->user();
        $user->full_name = trim($data['full_name']);
        $user->save();

        return response()->json(['user' => AuthController::userPayload($user)]);
    }

    public function createManagedUser(Request $request): JsonResponse
    {
        abort_unless(in_array($request->user()->role, ['admin', 'creator'], true), 403);
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8'],
            'full_name' => ['required', 'string', 'max:255'],
        ]);
        $data['email'] = mb_strtolower(trim($data['email']));

        $user = DB::transaction(function () use ($data, $request) {
            $user = User::create([
                'id' => (string) Str::uuid(),
                'full_name' => trim($data['full_name']),
                'email' => $data['email'],
                'password' => Hash::make($data['password']),
                'role' => 'user',
                'must_change_password' => true,
            ]);
            FinBizProvisioner::createBusiness($user);
            DB::table('audit_logs')->insert([
                'id' => (string) Str::uuid(),
                'actor_id' => $request->user()->id,
                'action' => 'create_user',
                'target_user_id' => $user->id,
                'details' => json_encode(['email' => $user->email]),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            return $user;
        });

        return response()->json(['id' => $user->id], 201);
    }

    public function updateRole(Request $request, User $user): JsonResponse
    {
        abort_unless($request->user()->role === 'creator', 403);
        $data = $request->validate(['role' => ['required', 'in:user,admin,creator']]);
        if ($user->is($request->user()) && $data['role'] !== 'creator') {
            throw ValidationException::withMessages([
                'role' => 'Creator tidak dapat menghapus peran Creator miliknya sendiri.',
            ]);
        }

        DB::transaction(function () use ($request, $user, $data) {
            $user->role = $data['role'];
            $user->save();
            DB::table('audit_logs')->insert([
                'id' => (string) Str::uuid(),
                'actor_id' => $request->user()->id,
                'action' => 'set_user_role',
                'target_user_id' => $user->id,
                'details' => json_encode(['role' => $data['role']]),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });

        return response()->json(['user' => AuthController::userPayload($user->refresh())]);
    }

    public function deleteManagedUser(Request $request, User $user): JsonResponse
    {
        $actor = $request->user();
        abort_if($user->is($actor), 422, 'Anda tidak dapat menghapus akun sendiri.');
        abort_unless(
            $actor->role === 'creator' || ($actor->role === 'admin' && $user->role === 'user'),
            403,
        );
        if ($user->role === 'creator' &&
            User::query()->where('role', 'creator')->count() <= 1) {
            abort(409, 'Akun Creator terakhir tidak dapat dihapus.');
        }

        DB::transaction(function () use ($actor, $user) {
            DB::table('audit_logs')->insert([
                'id' => (string) Str::uuid(),
                'actor_id' => $actor->id,
                'action' => 'delete_user',
                'target_user_id' => null,
                'details' => json_encode([
                    'target_user_id' => $user->id,
                    'email' => $user->email,
                ]),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $user->delete();
        });

        return response()->json(['success' => true]);
    }
}
