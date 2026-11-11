<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Throwable;

class ReceiptController extends Controller
{
    private const ALLOWED_MIME_TYPES = [
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf',
    ];

    public function upload(Request $request): JsonResponse
    {
        $data = $request->validate([
            'business_id' => ['required', 'uuid'],
            'transaction_id' => ['required', 'uuid'],
            'file' => ['required', 'file', 'max:10240', 'mimetypes:image/jpeg,image/png,image/webp,application/pdf'],
        ]);
        $transaction = $this->visibleTransactions($request->user())
            ->where('transactions.id', $data['transaction_id'])
            ->where('transactions.business_id', $data['business_id'])
            ->first();
        abort_if($transaction === null, 404);

        $file = $request->file('file');
        $contentType = $file->getMimeType();
        if (! in_array($contentType, self::ALLOWED_MIME_TYPES, true)) {
            throw ValidationException::withMessages(['file' => 'Tipe file bukti tidak didukung.']);
        }

        $originalName = mb_substr(
            preg_replace('/[^A-Za-z0-9._-]/', '_', basename($file->getClientOriginalName())) ?: 'bukti',
            0,
            120,
        );
        $path = $data['business_id'].'/'.$data['transaction_id'].'/'.Str::uuid().'-'.$originalName;
        $storedPath = Storage::disk('local')->putFileAs(
            dirname($path),
            $file,
            basename($path),
        );
        if ($storedPath === false) {
            throw new \RuntimeException('Bukti transaksi gagal disimpan.');
        }

        try {
            DB::table('transaction_attachments')->insert([
                'id' => (string) Str::uuid(),
                'business_id' => $data['business_id'],
                'transaction_id' => $data['transaction_id'],
                'storage_path' => $path,
                'original_name' => $originalName,
                'content_type' => $contentType,
                'byte_size' => $file->getSize(),
                'created_by' => $request->user()->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } catch (Throwable $error) {
            if (! Storage::disk('local')->delete($storedPath)) {
                report(new \RuntimeException('A temporary receipt could not be removed after metadata insertion failed.', 0, $error));
            }
            throw $error;
        }

        return response()->json(['storage_path' => $path], 201);
    }

    public function signedUrl(Request $request): JsonResponse
    {
        $data = $request->validate([
            'business_id' => ['required', 'uuid'],
            'transaction_id' => ['required', 'uuid'],
            'storage_path' => ['required', 'string'],
            'expires_in' => ['nullable', 'integer', 'between:30,3600'],
        ]);
        $this->validatePath($data['business_id'], $data['transaction_id'], $data['storage_path']);
        $attachment = $this->visibleAttachments($request->user())
            ->where('storage_path', $data['storage_path'])
            ->where('business_id', $data['business_id'])
            ->where('transaction_id', $data['transaction_id'])
            ->first();
        abort_if($attachment === null, 404);

        return response()->json([
            'url' => URL::temporarySignedRoute(
                'receipts.download',
                now()->addSeconds($data['expires_in'] ?? 300),
                ['attachment' => $attachment->id],
            ),
        ]);
    }

    public function download(string $attachment): StreamedResponse
    {
        $record = DB::table('transaction_attachments')->where('id', $attachment)->first();
        abort_if($record === null, 404);
        abort_unless(Storage::disk('local')->exists($record->storage_path), 404);

        return Storage::disk('local')->download(
            $record->storage_path,
            $record->original_name,
            ['Content-Type' => $record->content_type],
        );
    }

    public function delete(Request $request): JsonResponse
    {
        $data = $request->validate([
            'business_id' => ['required', 'uuid'],
            'transaction_id' => ['required', 'uuid'],
            'storage_path' => ['required', 'string'],
        ]);
        $this->validatePath($data['business_id'], $data['transaction_id'], $data['storage_path']);
        $attachment = $this->visibleAttachments($request->user())
            ->where('storage_path', $data['storage_path'])
            ->where('business_id', $data['business_id'])
            ->where('transaction_id', $data['transaction_id'])
            ->first();
        abort_if($attachment === null, 404);

        DB::table('transaction_attachments')->where('id', $attachment->id)->delete();
        if (! Storage::disk('local')->delete($attachment->storage_path)) {
            report(new \RuntimeException('Receipt metadata was deleted, but its file could not be removed.'));
        }

        return response()->json(['success' => true]);
    }

    private function visibleTransactions(User $user)
    {
        return DB::table('transactions')
            ->join('businesses', 'businesses.id', '=', 'transactions.business_id')
            ->when(
                $user->role === 'user',
                fn ($query) => $query->where('businesses.owner_id', $user->id),
            );
    }

    private function visibleAttachments(User $user)
    {
        return DB::table('transaction_attachments')
            ->join('businesses', 'businesses.id', '=', 'transaction_attachments.business_id')
            ->when(
                $user->role === 'user',
                fn ($query) => $query->where('businesses.owner_id', $user->id),
            )
            ->select('transaction_attachments.*');
    }

    private function validatePath(string $businessId, string $transactionId, string $path): void
    {
        $parts = explode('/', $path);
        if (count($parts) !== 3 ||
            $parts[0] !== $businessId ||
            $parts[1] !== $transactionId ||
            ! Str::isUuid($businessId) ||
            ! Str::isUuid($transactionId)) {
            throw ValidationException::withMessages(['storage_path' => 'Lokasi bukti transaksi tidak valid.']);
        }
    }
}
