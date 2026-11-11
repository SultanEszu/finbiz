# FinBiz

Aplikasi Flutter untuk mengelola keuangan bisnis. Backend menggunakan Laravel dan MySQL.

## Persiapan

Pasang Flutter, PHP 8.2+, Composer, dan MySQL. Buat database kosong bernama `finbiz`, lalu buka terminal di folder proyek.

## Menjalankan backend

```powershell
cd backend
composer install
Copy-Item .env.example .env
```

Isi konfigurasi database di `backend/.env`, kemudian jalankan:

```powershell
php artisan key:generate
php artisan migrate
php artisan serve --host 127.0.0.1 --port 8000
```

## Menjalankan aplikasi

Buka terminal baru di folder proyek:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## Catatan

- Jangan unggah `backend/.env` atau membagikan kredensial database.
- Data dari Supabase tidak disalin otomatis ke MySQL.
- Untuk perangkat fisik, ganti `127.0.0.1` dengan alamat IP komputer yang menjalankan backend.
