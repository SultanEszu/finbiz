# FinBiz

Aplikasi pengelolaan keuangan bisnis Flutter dengan Supabase Auth dan PostgreSQL.

## Konfigurasi Supabase

1. Pastikan skema project terlebih dahulu melalui Supabase Dashboard > **Database > Tables** dan riwayat migration. Jangan menjalankan migration awal pada skema/data yang sudah ada tanpa meninjau dampaknya.
2. Jalankan migration yang belum diterapkan secara berurutan: `supabase/migrations/20261109000000_initial_schema.sql`, lalu `supabase/migrations/20261109010000_finbiz_business_finance.sql`. Migration lanjutan memeriksa duplikasi pemilik bisnis dan relasi transaksi sebelum menambahkan constraint.
3. Setelah migration berhasil, jalankan `supabase/audit_auth_database.sql` di SQL Editor untuk melihat temuan integritas/RLS. Skrip ini hanya membaca data; tinjau temuannya sebelum merencanakan pembersihan.
4. Salin `supabase.example.json` menjadi `supabase.local.json` jika konfigurasi lokal belum ada. Isi URL project dan publishable key. Jangan pernah menaruh `service_role` key di aplikasi Flutter.
5. Jalankan aplikasi:

   ```powershell
   flutter pub get
   flutter run -d chrome --dart-define-from-file=supabase.local.json
   ```

6. Deploy Edge Function pengelolaan akun dan konfigurasikan secret hanya di Supabase:

   ```powershell
   supabase functions deploy manage-users
   supabase secrets set SUPABASE_URL=<url> SUPABASE_PUBLISHABLE_KEY=<publishable-key> SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
   ```

   Jangan masukkan `SUPABASE_SERVICE_ROLE_KEY` ke file konfigurasi Flutter atau repository.

Supabase diinisialisasi satu kali sebelum `runApp`. Jika konfigurasi atau inisialisasi gagal, aplikasi menampilkan pesan konfigurasi dan tidak memakai data dummy sebagai data produksi.

Saat login, aplikasi memanggil RPC `ensure_current_profile` setelah Auth menerima kredensial. RPC hanya dapat memperbaiki profil untuk `auth.uid()` yang sedang login, membuat role baru selalu `user`, dan tidak mengubah role profil yang telah ada. Profil creator yang hilang harus dipulihkan secara manual oleh pengelola dengan memeriksa dahulu UUID akun di `auth.users`; jangan membuat akun Auth kedua atau mengambil role dari metadata.

Bucket bukti transaksi dibuat privat oleh migration. Simpan file dengan pola path `<business_id>/<transaction_id>/<nama-file>`, ukuran maksimal 10 MiB, serta tipe JPEG, PNG, WebP, atau PDF. Upload dan URL bertanda tangan harus menggunakan sesi pengguna supaya policy Storage memvalidasi bisnis pemilik.

## Akun Creator awal

1. Di Supabase Dashboard buka **Authentication > Users**, cari `adminfinbiz@gmail.com` terlebih dahulu, dan jangan membuat akun kedua jika sudah tercantum.
2. Jika belum ada, pilih **Add user > Create new user**, gunakan email tersebut, masukkan password secara langsung pada Dashboard/password manager, dan tandai email terkonfirmasi sesuai kebijakan Anda. Jangan menaruh password di source, SQL, atau chat.
3. Terapkan migration schema terlebih dahulu. Lalu jalankan `supabase/bootstrap_creator.sql` di SQL Editor sebagai administrator. Skrip memeriksa akun Auth dan kecocokan UUID, tidak pernah menyisipkan ke `auth.users`, mengatur role hanya untuk email Creator yang ditentukan, dan memastikan bisnis/rekening/profil tersedia. Skrip aman dijalankan ulang dan tidak menghapus data.
4. Untuk akun yang sudah ada tetapi password tidak diketahui, gunakan **Authentication > Users > Send password recovery** atau alur reset password Auth. Untuk akun yang belum dikonfirmasi, konfirmasikan melalui Dashboard. Jangan reset password melalui SQL.
5. Login hanya dapat dipastikan setelah migration diterapkan, email dapat diverifikasi, dan password valid. Minta Creator mengganti password sementara melalui alur Auth setelah login jika kebijakan mengharuskannya.

Role aplikasi disimpan di `public.profiles`, bukan di `user_metadata`. Akun publik baru selalu dibuat sebagai `user`. Promosi role hanya tersedia melalui RPC `set_user_role` untuk Creator.

## Status integrasi

Auth dan routing role memakai Supabase Auth serta role dari `public.profiles`. Migrasi menyiapkan tabel bisnis/keuangan, RLS, saldo rekening, audit transaksi, dan bucket privat. Operasi administratif akun Auth tetap memerlukan Supabase Edge Function/server terpercaya; `service_role` tidak boleh dimasukkan ke aplikasi Flutter.
