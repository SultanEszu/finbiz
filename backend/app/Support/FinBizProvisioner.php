<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class FinBizProvisioner
{
    public static function createBusiness(User $user): string
    {
        $businessId = (string) Str::uuid();
        $now = now();

        DB::table('businesses')->insert([
            'id' => $businessId,
            'owner_id' => $user->id,
            'business_name' => trim($user->full_name) !== ''
                ? trim($user->full_name).' - FinBiz'
                : 'Bisnis FinBiz',
            'description' => '',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::table('business_settings')->insert([
            'business_id' => $businessId,
            'currency_code' => 'IDR',
            'time_zone' => 'Asia/Jakarta',
            'fiscal_start_month' => 1,
            'preferences' => json_encode((object) []),
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::table('cash_accounts')->insert([
            'id' => (string) Str::uuid(),
            'business_id' => $businessId,
            'name' => 'Kas utama',
            'account_type' => 'cash',
            'opening_balance' => 0,
            'is_active' => true,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        foreach ([
            ['Makanan & Minuman', 'expense', 'restaurant', 4292617766],
            ['Perumahan', 'expense', 'home', 4279646815],
            ['Transportasi', 'expense', 'directions_car', 4281902555],
            ['Gaji', 'income', 'trending_up', 4279673674],
            ['Tabungan', 'income', 'savings', 4281902555],
        ] as [$name, $type, $icon, $color]) {
            DB::table('categories')->insert([
                'id' => (string) Str::uuid(),
                'user_id' => $user->id,
                'business_id' => $businessId,
                'name' => $name,
                'type' => $type,
                'icon_name' => $icon,
                'color_value' => $color,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        return $businessId;
    }

    public static function businessIdFor(User $user): string
    {
        $businessId = DB::table('businesses')
            ->where('owner_id', $user->id)
            ->value('id');

        if ($businessId !== null) {
            return $businessId;
        }

        return DB::transaction(fn () => self::createBusiness($user));
    }
}
