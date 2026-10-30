# E-Absensi — Database

Dokumen operasional: cara menjalankan skema, konvensi migrasi, dan backup/restore. Pembahasan desain (ERD, ringkasan tabel, deviasi PRD, keputusan teknis, peta arsitektur) ada di [DESAIN.md](./DESAIN.md).

| Item | Nilai |
|---|---|
| DBMS | PostgreSQL (diuji pada PostgreSQL 18.6 / Windows) |
| Folder DDL | [`sql/`](./sql) — migrasi `NNN_keterangan.sql`, dijalankan berurutan dari `001` |
| Backup | [`absensi.dump`](./dump/absensi.dump) (snapshot skema + seed) |
| Info/Desain | [DESAIN.md](./DESAIN.md) |

## Cara menjalankan

### DB baru (setup dari nol)

Buat database dengan encoding UTF8, lalu jalankan **seluruh** migrasi di `database\sql\` — urutannya dijamin nama file `NNN_...` (zero-padded), jadi perintah tidak perlu diubah saat ada file baru:

```powershell
createdb -U user lu -E UTF8 absensi

Get-ChildItem database\sql\*.sql | Sort-Object Name | ForEach-Object {
    Write-Host "==> $($_.Name)"
    psql -U user lu -d absensi -v ON_ERROR_STOP=1 -f $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Gagal di $($_.Name)" }
}
```

Cek hasilnya:

```sql
SELECT count(*) FROM roles;                          -- 7 (seed tetap)
SELECT code, module FROM permissions ORDER BY code;  -- daftar izin yang aktif
```

### DB yang sudah berjalan

Jalankan **hanya file migrasi terbaru** yang belum pernah dijalankan pada DB tersebut — file lama tidak perlu diulang karena sudah terpasang:

```powershell
# ganti NNN_keterangan.sql dengan nama file migrasi terbaru
psql -U user lu -d absensi -v ON_ERROR_STOP=1 -f database\sql\NNN_keterangan.sql
```

**Idempotensi:** seluruh file `.sql` **aman dijalankan berulang** (`CREATE ... IF NOT EXISTS`, seed `ON CONFLICT DO NOTHING`, `GRANT`/`ALTER` tidak error bila sudah terpenuhi).

## Konvensi file migrasi

| Aturan | Rincian |
|---|---|
| Penamaan | `NNN_keterangan.sql` berurutan — `003_...`, `004_...`, dst. Nama mencerminkan perubahan |
| Source of truth | **File SQL** — setiap perubahan skema = **file baru**. File yang sudah pernah dijalankan bersifat **final**: tidak diedit lagi, perbaikan apa pun = file migrasi berikutnya |
| Urutan | File dijalankan menaik (`001` → `002` → `003` → ...). Jangan pernah menyisipkan nomor di tengah |
| Isi file | Keterangan perubahan (komentar) → DDL → `COMMENT ON ...` sinkron ke DB |
| Transaksi | Dibungkus `BEGIN;` ... `COMMIT;` |
| Idempotent | Aman dijalankan berulang pada DB dengan status apa pun |
| Encoding | **Murni ASCII** — tidak boleh memuat `→`, `—`, atau emoji agar aman di koneksi encoding apa pun |

### Proses penambahan permission (Epic 3+)

Setiap epic baru **wajib menambahkan permission modulnya** ke tabel `permissions` + pemberiannya ke `role_permissions` lewat file migrasi masing-masing (contoh: `004` menambahkan 7 permission Epic 2, semuanya untuk role `admin`). FK ke `users.id` pada tabel epic berikutnya juga wajib `ON DELETE RESTRICT` (dibutuhkan F2.6 — akun hanya boleh dihapus tanpa riwayat).

## Berbagi database (dump & restore)

Menyalin database **beserta isinya** ke mesin lain memakai `pg_dump` format custom. Untuk setup dari nol (skema + seed saja), kirim **seluruh file `.sql` di folder [`sql/`](./sql/)** — penerimanya cukup ikut bagian *Cara menjalankan*.

### Membuat dump

```powershell
pg_dump -U user lu -Fc --no-owner -f database\dump\absensi.dump absensi
```

| Opsi | Fungsi |
|---|---|
| `-Fc` | format custom terkompresi; direstore dengan `pg_restore` |
| `--no-owner` | objek dimiliki oleh role yang me-restore — tidak bergantung pada role pembuat |
| tanpa `--no-privileges` | grant `PUBLIC` ikut terbawa (lihat [DESAIN.md](./DESAIN.md) bagian 6.2) |

Dump dibuat tanpa referensi role tertentu, sehingga aman direstore di cluster mana pun. `pg_dumpall --globals-only` **tidak** dipakai untuk dibagikan karena file tersebut memuat hash password seluruh role cluster.

### Restore dump (bila menerima `absensi.dump`)

Dipakai bila kamu menerima file `absensi.dump` dari tim/QA (snapshot skema + data). Untuk DB kosong yang dibangun dari file SQL, lewati bagian ini.

Prasyarat: PostgreSQL terpasang, versi `pg_dump`/`pg_restore` di mesin penerima sama atau lebih baru.

```powershell
# 1. Buat database dengan encoding UTF8
createdb -U <user> -E UTF8 absensi

# 2. Restore dump
pg_restore -U <user> --no-owner -d absensi absensi.dump

# 3. Terapkan akses & encoding (002 idempotent, aman dijalankan berulang)
psql -U <user> -d absensi -v ON_ERROR_STOP=1 -f database\sql\002_access_and_encoding.sql
```

Dua catatan operasional:

- **`-U <user>` wajib diisi.** Tanpa itu utilitas PostgreSQL memakai nama user sistem operasi; bila tidak cocok dengan role di server, muncul `password authentication failed for user "..."`.
- **Langkah 3 wajib** karena dua hal tidak ikut terdump: setting level database (`client_encoding`) dibentuk ulang oleh `002`, dan `ALTER DEFAULT PRIVILEGES` dibuat untuk role penerima sehingga objek yang dibuat berikutnya otomatis punya hak baca-tulis.

### Verifikasi setelah restore

```sql
SHOW client_encoding;                 -- UTF8
SELECT count(*) FROM roles;           -- 7 (seed tetap)
SELECT code, module FROM permissions ORDER BY code;  -- izin yang ikut dump
SELECT count(*) FROM users;           -- sesuai isi saat dump dibuat
SELECT count(*) FROM pg_default_acl;  -- 2 baris, milik role penerima
SELECT current_user;                  -- role yang me-restore
```
