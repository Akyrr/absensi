# Desain Database — E-Absensi

**Scope dokumen ini:** Epic 1 — *Authentication & Account Management* + Epic 2 — *User & Role Management* + Epic 3 — *Master Data* + Epic 4 — *Jadwal* + Epic 5 — *Absensi Siswa* + Epic 6 — *Kehadiran Guru & QR* (detail, siap implementasi) + peta arsitektural seluruh sistem.

Cara menjalankan skema, konvensi migrasi, dan backup/restore ada di [README.md](./README.md).

| Item | Nilai |
|---|---|
| DBMS | PostgreSQL (diuji pada PostgreSQL 18.6 / Windows) |
| File DDL | [`001_epic1_auth.sql`](./sql/001_epic1_auth.sql) (skema Epic 1) · [`002_access_and_encoding.sql`](./sql/002_access_and_encoding.sql) (akses team + encoding) · [`003_add_failed_login_at.sql`](./sql/003_add_failed_login_at.sql) (jendela lockout 15 menit) · [`004_epic2_user_role_management.sql`](./sql/004_epic2_user_role_management.sql) (Epic 2: status nonaktif, metadata role, RBAC) · [`005_otp_length_comment.sql`](./sql/005_otp_length_comment.sql) (komentar OTP 6 karakter) · [`006_drop_username_format_check.sql`](./sql/006_drop_username_format_check.sql) (cabut CHECK format username Epic 2) · [`007_activity_logs.sql`](./sql/007_activity_logs.sql) (fondasi log aktivitas Epic 13) · [`008_add_archived_at.sql`](./sql/008_add_archived_at.sql) (`users.archived_at`) · [`009_activity_logs_target.sql`](./sql/009_activity_logs_target.sql) (target generik log) · [`010_academic_years.sql`](./sql/010_academic_years.sql) (tahun ajaran) · [`011_subjects.sql`](./sql/011_subjects.sql) (mata pelajaran) · [`012_teachers.sql`](./sql/012_teachers.sql) (profil guru) · [`013_classes.sql`](./sql/013_classes.sql) (kelas) · [`014_students.sql`](./sql/014_students.sql) (profil siswa + sinkron NISN) · [`015_teacher_subjects.sql`](./sql/015_teacher_subjects.sql) (mapel guru) · [`016_schedules.sql`](./sql/016_schedules.sql) (jadwal) · [`017_permissions_epic3_epic4.sql`](./sql/017_permissions_epic3_epic4.sql) (permission Epic 3/4) · [`018_backfill_students.sql`](./sql/018_backfill_students.sql) (backfill profil siswa) · [`019_teacher_attendances.sql`](./sql/019_teacher_attendances.sql) (kehadiran guru) · [`020_student_attendances.sql`](./sql/020_student_attendances.sql) (absensi siswa) · [`021_leave_requests.sql`](./sql/021_leave_requests.sql) (izin/sakit) · [`022_permission_letters.sql`](./sql/022_permission_letters.sql) (surat tatib/dispensasi) · [`023_alpha_tracking.sql`](./sql/023_alpha_tracking.sql) (Alpha harian + peringatan) · [`024_permissions_epic5_epic6.sql`](./sql/024_permissions_epic5_epic6.sql) (permission Epic 5/6) · [`025_teacher_attendance_correction.sql`](./sql/025_teacher_attendance_correction.sql) (koreksi status kehadiran guru) |
| Sumber requirement | `PRD Utama.docx` (revisi 3) + `PRD EPIC 1.docx` (v2.1) + `PRD EPIC 2.docx` (v1.0) + `PRD EPIC 3.docx` (v1.1) + `PRD EPIC 4.docx` (v1.0) + `PRD EPIC 5.docx` (v1.0) + `PRD EPIC 6.docx` (v1.0). **Catatan:** backend menyebut PRD Epic 2 v1.3, tetapi file v1.3 belum ada di workspace; `archived_at` dan tabel `activity_logs` ditambahkan berdasarkan kebutuhan backend + kesepakatan tim, bukan kutipan v1.3 |
| Tabel | `roles`, `users`, `user_roles`, `otp_codes`, `sessions` (Epic 1) · `permissions`, `role_permissions` (Epic 2) · `activity_logs` (fondasi Epic 13, dibuat di Epic 2) · `academic_years`, `subjects`, `teachers`, `classes`, `students`, `teacher_subjects` (Epic 3) · `schedules` (Epic 4) · `teacher_attendances` (Epic 6) · `student_attendances`, `leave_requests`, `permission_letters`, `alpha_daily_summaries`, `alpha_warning_logs` (Epic 5) |

## 1. ERD

```mermaid
erDiagram
    users ||--o{ user_roles : "memiliki (multi-role)"
    roles ||--o{ user_roles : "diamparkan ke"
    users ||--o{ otp_codes   : "menerima"
    users ||--o{ sessions    : "login di"
    roles ||--o{ role_permissions : "diberi izin"
    permissions ||--o{ role_permissions : "dipakai oleh"
    users ||--o| students : "profil siswa (Epic 3)"
    users ||--o| teachers : "profil guru (Epic 3)"
    users ||--o{ classes : "wali kelas (Epic 9)"
    users ||--o{ schedules : "created_by"
    academic_years ||--o{ classes : "memiliki"
    classes ||--o{ students : "kelas saat ini"
    teachers ||--o{ teacher_subjects : "mengampu"
    subjects ||--o{ teacher_subjects : "diampu"
    classes ||--o{ schedules : "dijadwalkan"
    subjects ||--o{ schedules : "mapel"
    teachers ||--o{ schedules : "pengampu"
    schedules ||--o| teacher_attendances : "kehadiran guru"
    teachers ||--o{ teacher_attendances : "guru terkonfirmasi"
    users ||--o{ teacher_attendances : "pembuat QR / anotasi"
    schedules ||--o{ student_attendances : "absensi siswa"
    students ||--o{ student_attendances : "dinilai"
    classes ||--o{ student_attendances : "snapshot kelas"
    academic_years ||--o{ student_attendances : "snapshot tahun"
    students ||--o{ leave_requests : "izin/sakit"
    classes ||--o{ leave_requests : "snapshot kelas"
    users ||--o{ leave_requests : "reviewer"
    students ||--o{ permission_letters : "surat"
    users ||--o{ permission_letters : "pengunggah"
    students ||--o{ alpha_daily_summaries : "alpha harian"
    classes ||--o{ alpha_daily_summaries : "snapshot kelas"
    academic_years ||--o{ alpha_daily_summaries : "tahun ajaran"
    students ||--o{ alpha_warning_logs : "peringatan"
    academic_years ||--o{ alpha_warning_logs : "tahun ajaran"

    roles {
        smallint id PK
        varchar name UK "admin, siswa, ..."
        varchar description
        varchar label "nama tampilan UI"
        varchar category "staff | student"
        boolean is_assignable "true = role dapat diatur F2.5"
        timestamptz created_at
    }

    users {
        bigint id PK
        varchar name
        varchar email UK "lowercase, login + OTP"
        varchar username UK "opsional, login Epic 1; format Epic 2 ditunda"
        varchar password_hash "nullable (akun Google / staf tanpa kredensial)"
        varchar nisn UK "10 digit, hanya siswa"
        varchar google_id UK "opsional"
        varchar avatar_url
        boolean is_active "true/false saja"
        varchar inactive_reason "F2.4: graduated|transferred|other"
        timestamptz deactivated_at "F2.4"
        timestamptz archived_at "pengarsipan; hanya saat nonaktif"
        smallint failed_login_attempts "lockout 5x/15 menit"
        timestamptz failed_login_at "gagal terakhir, jendela 15 menit"
        timestamptz locked_until
        timestamptz password_changed_at
        timestamptz created_at
        timestamptz updated_at
    }

    user_roles {
        bigint id PK
        bigint user_id FK
        smallint role_id FK
        timestamptz created_at
    }

    otp_codes {
        bigint id PK
        bigint user_id FK
        varchar code_hash "hash, bukan teks asli"
        varchar purpose "change_password|reset_password"
        timestamptz expired_at
        timestamptz last_sent_at "cooldown resend"
        boolean is_used
        smallint attempt_count "maks 5"
        timestamptz created_at
    }

    sessions {
        bigint id PK
        bigint user_id FK
        varchar refresh_token_hash UK
        varchar device_info
        inet ip_address
        varchar user_agent
        timestamptz expired_at
        timestamptz revoked_at "logout / ganti password"
        timestamptz last_used_at
        timestamptz created_at
    }

    academic_years {
        bigint id PK
        varchar name UK "contoh 2026/2027"
        varchar active_semester "semester_1|semester_2"
        date start_date
        date end_date "nullable"
        boolean is_active "maks 1 true"
        timestamptz updated_at
    }

    subjects {
        bigint id PK
        varchar code UK
        varchar name
        boolean is_active
        timestamptz updated_at
    }

    teachers {
        bigint id PK
        bigint user_id FK,UK
        varchar nip
        timestamptz updated_at
    }

    classes {
        bigint id PK
        varchar name "unik per tahun ajaran"
        smallint grade_level "10|11|12"
        bigint academic_year_id FK
        bigint wali_kelas_user_id FK "nullable, Epic 9"
        boolean is_active
        timestamptz updated_at
    }

    students {
        bigint id PK
        bigint user_id FK,UK
        varchar nisn UK "10 digit"
        bigint class_id FK "nullable"
        timestamptz updated_at
    }

    teacher_subjects {
        bigint teacher_id PK,FK
        bigint subject_id PK,FK
        timestamptz created_at
    }

    schedules {
        bigint id PK
        date schedule_date
        time start_time
        time end_time
        bigint class_id FK
        bigint subject_id FK
        bigint teacher_id FK
        varchar schedule_type "pelajaran|kegiatan"
        varchar activity_name "nullable"
        bigint created_by FK
        integer version "optimistic locking"
        timestamptz updated_at
    }

    teacher_attendances {
        bigint id PK
        bigint schedule_id FK,UK "hanya pelajaran"
        varchar status "hadir|guru_pengganti|tidak_hadir"
        bigint confirmed_teacher_id FK "nullable"
        varchar confirmation_method "qr_scan|kode_cadangan|koreksi_admin"
        timestamptz confirmed_at "nullable"
        bigint generated_by_user_id FK "nullable"
        varchar generated_by_role "siswa_inti|wali_kelas"
        text keterangan "nullable"
        bigint keterangan_updated_by FK "nullable"
        timestamptz updated_at
    }

    student_attendances {
        bigint id PK
        bigint schedule_id FK
        bigint student_id FK
        bigint class_id FK "snapshot"
        bigint academic_year_id FK "snapshot"
        varchar status "hadir|izin|sakit|alpha|dispensasi"
        varchar source "ceklis_guru|fallback_wali_kelas|auto_from_leave_request|manual_edit"
        bigint recorded_by FK "penulis terakhir"
        varchar note "nullable"
        integer version "optimistic locking"
        timestamptz updated_at
    }

    leave_requests {
        bigint id PK
        bigint student_id FK
        bigint class_id FK "snapshot"
        varchar type "izin|sakit"
        date date "unik per siswa"
        varchar reason
        varchar evidence_file_url
        varchar status "draft|disetujui|ditolak"
        bigint reviewed_by FK "nullable"
        timestamptz reviewed_at "nullable"
        timestamptz created_at
    }

    permission_letters {
        bigint id PK
        bigint student_id FK
        varchar type "pulang_tatib|dispensasi"
        bigint uploaded_by FK
        varchar evidence_file_url
        varchar note "nullable"
        timestamptz created_at
    }

    alpha_daily_summaries {
        bigint student_id PK,FK
        date date PK
        bigint academic_year_id FK
        bigint class_id FK "snapshot"
        smallint lesson_total
        smallint lesson_alpha
        boolean is_alpha "> 75 persen"
        timestamptz updated_at
    }

    alpha_warning_logs {
        bigint id PK
        bigint student_id FK
        bigint academic_year_id FK
        smallint threshold "3|5|9"
        smallint alpha_days
        timestamptz triggered_at
    }

    permissions {
        bigint id PK
        varchar code UK "format module.action"
        varchar module
        varchar description
    }

    role_permissions {
        smallint role_id PK,FK
        bigint permission_id PK,FK
    }

    activity_logs {
        bigint id PK
        bigint actor_user_id "tanpa FK; NULL = sistem"
        bigint target_user_id "tanpa FK; tetap ada setelah akun dihapus"
        varchar target_type "USER|CLASS|SUBJECT|..."
        bigint target_id "tanpa FK; target generik"
        varchar action "kode event kanonik"
        jsonb snapshot "aman; tanpa data sensitif"
        timestamptz created_at
    }

    note right of activity_logs
        Tanpa FK (actor & target tidak di-relasikan)
        agar log tetap utuh setelah target dihapus
    end note
```

## 2. Ringkasan per tabel

### `roles` — 7 role (seed) + metadata Epic 2
Referensi tetap. Diisi otomatis saat import: `admin`, `waka_kurikulum`, `waka_kesiswaan`, `guru_mapel`, `wali_kelas`, `siswa_inti`, `siswa`.

`wali_kelas` dan `siswa_inti` adalah **role tambahan** pada akun Guru/Siswa (bukan akun terpisah) — didukung oleh relasi many-to-many `user_roles`.

Metadata Epic 2 (`004`): `label` (nama tampilan UI), `category` (`staff`/`student` — dasar validasi kombinasi role), `is_assignable` (`true` untuk `admin`, `waka_kurikulum`, `waka_kesiswaan`, `guru_mapel`; `false` = role terkunci yang tidak boleh disentuh Admin lewat F2.5).

### `users` — satu baris = satu akun login
- `email` wajib, unik **case-insensitive** (index `lower(email)`), disimpan lowercase oleh trigger.
- `password_hash` nullable untuk akun Google-only; format hash dicek minimal diawali `$`. CHECK Epic 1 yang mewajibkan "password atau Google" **dihapus di `004`** — F2.2 membuat akun staf tanpa kredensial; login pertama lewat link/Google/Reset Password.
- `nisn` nullable + unik, format 10 digit — hanya untuk akun siswa.
- Kolom lockout (3): `failed_login_attempts` (counter), `failed_login_at` (waktu kegagalan terakhir — dasar jendela 15 menit), `locked_until` (hasil kunci). Counter direset bila jeda sejak `failed_login_at` melebihi 15 menit, sehingga "5 gagal dalam 15 menit -> kunci 15 menit" sesuai PRD Bagian 3.B; kegagalan yang tersebar berhari-hari tidak ikut mengakumulasi. `NULL` pada `failed_login_at` = belum pernah gagal atau baru direset.
- `is_active` boolean — **hanya 2 status akun** (tidak ada pending/locked permanen, PRD Bagian 3.A).
- Kolom status nonaktif (Epic 2 F2.4): `inactive_reason` (`graduated` lulus / `transferred` pindah / `other` lainnya) + `deactivated_at`. `CHECK ck_users_inactive_state` menegakkan konsistensi dua arah: aktif = keduanya `NULL`; nonaktif = keduanya terisi.
- `archived_at` (lewat `008`) — waktu akun diarsipkan; `NULL` = belum diarsipkan. `CHECK ck_users_archived_state` mewajibkan `is_active = false` bila kolom ini terisi. Mengisi `archived_at` wajib disertai `inactive_reason` + `deactivated_at` (dituntut `ck_users_inactive_state`), dan **wajib dikosongkan saat akun diaktifkan kembali**. Partial index `ix_users_archived` hanya memuat baris terarsip.
- `username` tetap ada dan **unik** (`uq_users_username`) karena Epic 1 memakai username untuk login/registrasi. CHECK format Epic 2 (`ck_users_username_format`) **dicabut di `006`**: aturan format masih ditunda sampai PRD Epic 2 final, sementara Epic 1 menerima 3–50 karakter case-sensitive. Bila format final, pasang kembali lewat migrasi baru.
- Tidak ada kolom `deleted_at` — penonaktifan = `is_active = false` (+ alasan & waktu); pengarsipan = `archived_at`.
- Index `ix_users_name` untuk pencarian daftar akun (F2.1). Pencarian `contains` (`%q%`) tidak memakai index btree; bila terbukti lambat, solusinya migrasi terpisah dengan `pg_trgm` (GIN) — tidak dicampur di `004` agar dump tidak bergantung pada extension.

### `user_roles` — kunci fitur F1.8 (union)
`UNIQUE(user_id, role_id)` mencegah role ganda; `FK role_id ON DELETE RESTRICT` (role master tak boleh terhapus selama dipakai); `FK user_id ON DELETE CASCADE`.

**Tidak ada kolom "role aktif"** — baik di `user_roles` maupun `sessions`. Otorisasi Backend selalu mengambil seluruh set role dari tabel ini (union), sesuai PRD utama KS-32.

### `otp_codes` — dipakai F1.4 (ganti) & F1.5 (reset)
- `purpose` di-`CHECK` hanya `change_password` / `reset_password` → isolasi purpose tereksekusi di level DB.
- `code_hash` — OTP **6 karakter** (huruf besar + angka, tanpa karakter ambigu) tidak pernah disimpan plaintext. Komentar tabel disinkronkan lewat `005_otp_length_comment.sql`.
- `last_sent_at` — dasar cooldown resend (60 detik) & batas 5 resend/jam.
- `attempt_count` — maksimal 5 percobaan salah per kode; melebihi batas itu kode dianggap tidak valid.
- `is_used` — sekali pakai; resend baru = tandai baris lama `is_used = true` (hanya 1 OTP aktif per user per purpose).
- Partial index `WHERE is_used = false` mempercepat "ambil OTP aktif terbaru".

### `sessions` — 1 baris = 1 device
- `refresh_token_hash` unik (access token 15 menit tidak disimpan di DB).
- `revoked_at` — **soft revoke**: logout mengisi kolom ini hanya untuk baris tersebut; ganti/reset password mengisi untuk **seluruh** baris milik user (`UPDATE sessions SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL`, didukung partial index `ix_sessions_user_live`).
- Multi-device tanpa batas jumlah sesi (PRD F1.7).
- Kolom `ip_address`, `user_agent`, `last_used_at` = tambahan untuk audit/keamanan.
- Penonaktifan akun (F2.4) juga mencabut seluruh sesi aktif — Backend memakai mekanisme revoke yang sama, ditambah pengecekan `is_active` pada setiap request.

### `permissions` — kamus izin (Epic 2 F2.7)
`code` unik berformat `module.action` (huruf kecil, titik) — dipakai Backend pada middleware `requirePermission`. `module` = pengelompokan Matriks Hak Akses; `description` = teks human-readable untuk UI Admin. Diisi oleh seeder/migrasi epic masing-masing — `004` menanam 7 permission Epic 2 (`account.*`, `role.assign`, `permission.view`).

### `role_permissions` — pemberian izin per role (Epic 2 F2.7)
PK gabungan `(role_id, permission_id)`; `role_id` FK **ON DELETE RESTRICT** (role master tidak boleh terhapus selama izin terpasang); `permission_id` FK **ON DELETE CASCADE** (permission dicabut = pemberiannya ikut hilang); index `ix_role_permissions_permission` untuk pertanyaan "role mana saja yang punya izin ini".

Matriks bersifat **baku** (PRD Bagian 11): pemberian izin diubah lewat migrasi/seeder, **tidak** lewat UI. Seluruh 7 permission Epic 2 diberikan ke `admin` saja. Epic berikutnya menambahkan permission modulnya sendiri ke kedua tabel ini.

### `activity_logs` — fondasi log aktivitas (dibuat di Epic 2, dimiliki Epic 13)
Tabel ini dibuat lebih awal karena AC Epic 2 menuntut setiap operasi CUD menghasilkan event yang bisa diperiksa. **Kepemilikan tetap Epic 13**: epic tersebut menambah kolom/fitur tampilan & filter, bukan membuat ulang tabel.

- `actor_user_id` — pelaku operasi (id `users`); `NULL` berarti pelaku sistem/proses otomatis. **Tanpa FK** agar id pelaku tetap tersimpan walau akunnya dihapus.
- `target_user_id` — akun yang menjadi target; **tanpa FK** agar log & snapshot tetap utuh setelah akun target dihapus permanen.
- `action` — kode event kanonik Epic 2 (7): `ACCOUNT_CREATED`, `ACCOUNT_UPDATED`, `ACCOUNT_DEACTIVATED`, `ACCOUNT_ACTIVATED`, `ROLE_ASSIGNED`, `ROLE_REVOKED`, `ACCOUNT_DELETED`. **Tanpa CHECK** — epic berikutnya menambah kode sendiri tanpa migrasi.
- `snapshot` — snapshot/diff aman untuk audit. **Dilarang** memuat `password_hash`, `google_id`, token, atau OTP. Aturan ini tidak bisa ditegakkan DB, wajib diuji di Backend.
- Index: `(target_user_id, created_at DESC)`, `(action, created_at DESC)`, `(actor_user_id, created_at DESC)`, dan `(created_at DESC)` untuk daftar kronologis.
- `target_type` + `target_id` (lewat `009`) — target generik untuk event Epic 3/4: `USER`, `STUDENT`, `TEACHER`, `CLASS`, `SUBJECT`, `ACADEMIC_YEAR`, `SCHEDULE`. Keduanya **tanpa FK** dan tanpa CHECK agar tipe target bisa bertambah. Index `(target_type, target_id, created_at DESC)`.
- Backend menulis log **dalam transaksi yang sama** dengan operasi CUD agar operasi sukses tidak kehilangan event.

### Tabel Epic 3 — master data

#### `academic_years` (010)
- `name` unik; `active_semester` hanya `semester_1` / `semester_2`; `end_date` boleh `NULL` dan tidak boleh sebelum `start_date`.
- Partial unique index `uq_academic_years_active` pada `is_active WHERE is_active` menjamin **maksimal satu tahun ajaran aktif**.
- Aktivasi tahun baru harus satu transaksi dengan penonaktifan tahun lama. Unique violation diterjemahkan Backend menjadi 409.

#### `subjects` (011)
- `code` unik dan tidak boleh kosong; `name` tidak boleh kosong; `is_active` untuk nonaktifkan tanpa hapus.
- Mapel yang sudah dipakai `teacher_subjects` atau `schedules` tidak bisa dihapus (FK RESTRICT).

#### `teachers` (012)
- `user_id` unik + FK `users.id` **ON DELETE RESTRICT**; satu akun guru hanya punya satu profil.
- `nip` wajib, tidak harus unik. Validasi role `guru_mapel` dilakukan Backend karena role ada di `user_roles`.

#### `classes` (013)
- `UNIQUE(name, academic_year_id)`; `grade_level` hanya 10/11/12; `academic_year_id` FK RESTRICT.
- `wali_kelas_user_id` menunjuk `users.id`, nullable, FK SET NULL; pengisian menjadi kewenangan Epic 9 (read-only di Epic 3).
- `is_active` untuk nonaktifkan; hapus permanen hanya jika belum dipakai `students.class_id` atau `schedules`.

#### `students` (014)
- `user_id` unik + FK `users.id` **ON DELETE RESTRICT**; `nisn` unik, 10 digit, wajib.
- `class_id` nullable (`NULL` = Tanpa Kelas), FK RESTRICT. Riwayat kelas belum dimodelkan; akan ditangani Epic 9/10.
- Trigger `fn_sync_students_users_nisn` menyinkronkan `students.nisn` dan `users.nisn` dua arah. `students.nisn` adalah acuan akademik; `users.nisn` tetap dipakai login/registrasi Epic 1.
- Backfill `018` membuat profil untuk akun ber-role `siswa` yang sudah punya NISN. Registrasi baru wajib membuat `students` dalam transaksi yang sama (perubahan Backend).

#### `teacher_subjects` (015)
- PK gabungan `(teacher_id, subject_id)`; FK `teacher_id` CASCADE, `subject_id` RESTRICT.
- CASCADE pada guru tetap tertahan `schedules.teacher_id` (RESTRICT) bila guru sudah punya jadwal.

### Tabel Epic 4 — jadwal

#### `schedules` (016)
- Satu baris = satu kejadian pada `schedule_date` tertentu (bukan pola mingguan).
- Kolom: `schedule_date`, `start_time`, `end_time`, `class_id`, `subject_id`, `teacher_id`, `schedule_type` (`pelajaran`/`kegiatan`), `activity_name`, `created_by`, `version`, `updated_at`.
- `UNIQUE(class_id, schedule_date, start_time)` mencegah slot kelas ganda; `UNIQUE(teacher_id, schedule_date, start_time)` mencegah guru mengajar dua kelas pada jam mulai yang sama.
- Exclusion constraint `ex_schedules_class_overlap` dan `ex_schedules_teacher_overlap` menolak slot yang **bertumpuk** (bukan hanya jam mulai identik), memakai `tsrange(schedule_date + start_time, schedule_date + end_time)` dan `btree_gist`.
- `CHECK ck_schedules_activity`: tipe `pelajaran` wajib `activity_name NULL`; tipe `kegiatan` wajib nama tidak kosong.
- **Deviasi:** `subject_id` tetap `NOT NULL` saat kegiatan agar jurnal tetap punya mapel. Nama kegiatan hanya untuk tampilan.
- `version` naik otomatis lewat `trg_schedules_bump_version`; Backend memakai `WHERE id = ? AND version = ?` dan mengembalikan 409 bila 0 baris.
- Semua FK ke `classes`/`subjects`/`teachers` RESTRICT; `created_by` SET NULL.

### Tabel Epic 6 — kehadiran guru

#### `teacher_attendances` (019)
- Satu baris per `schedule_id` (`UNIQUE`); hanya jadwal `schedule_type = 'pelajaran'`.
- Kolom: `status` (`hadir`/`guru_pengganti`/`tidak_hadir`), `confirmed_teacher_id`, `confirmation_method` (`qr_scan`/`kode_cadangan`/`koreksi_admin`), `confirmed_at`, `generated_by_user_id`, `generated_by_role`, `keterangan`, `keterangan_updated_by`, `created_at`, `updated_at`.
- Trigger `fn_teacher_attendances_guard` menolak jadwal kegiatan dan **menentukan status**: `confirmed_teacher_id = schedules.teacher_id` -> `hadir`; berbeda -> `guru_pengganti`. Klien tidak boleh mengirim status sendiri.
- CHECK pasangan: `tidak_hadir` wajib mengosongkan seluruh kolom konfirmasi/QR; status lain wajib mengisi guru + waktu. Konfirmasi normal (`qr_scan`/`kode_cadangan`) wajib punya generator QR; koreksi `koreksi_admin` (lewat `025`) boleh tanpa generator.
- F6.3 memakai `INSERT ... ON CONFLICT (schedule_id) DO NOTHING`; race dengan scan guru diselesaikan UNIQUE.
- FK `schedule_id` dan `confirmed_teacher_id` RESTRICT; dua kolom user SET NULL. Index `ix_schedules_lesson_end` (`schedule_date`, `end_time`) parsial untuk job auto-absent.
- **QR/kode tidak disimpan di DB** — cache TTL 30 detik sesuai PRD.

### Tabel Epic 5 — absensi siswa

#### `student_attendances` (020)
- Satu baris per `(schedule_id, student_id)`; hanya jadwal pelajaran.
- `class_id` dan `academic_year_id` adalah **snapshot** yang diisi trigger dari `schedules`/`classes`; UPDATE tidak boleh mengubah identitas maupun snapshot.
- `status` 5 nilai (`hadir`, `izin`, `sakit`, `alpha`, `dispensasi`); `source` 4 nilai (`ceklis_guru`, `fallback_wali_kelas`, `auto_from_leave_request`, `manual_edit`).
- `recorded_by` = penulis terakhir, NOT NULL, FK RESTRICT. `note` dipertahankan saat F5.7 menimpa status.
- `version` + trigger `fn_bump_version` untuk optimistic locking F5.3/F5.4.
- **Deviasi:** snapshot kelas/tahun ajaran tidak ada di PRD; tanpa snapshot, rekap historis per kelas salah setelah siswa pindah kelas.

#### `leave_requests` (021)
- Satu pengajuan per siswa per tanggal: `UNIQUE(student_id, date)` **penuh**, bukan parsial `status = 'draft'`.
- `class_id` snapshot saat pengajuan; dipakai F5.7 untuk mencari jadwal pelajaran kelas tersebut.
- `reason` dan `evidence_file_url` wajib; `type` (`izin`/`sakit`); `status` (`draft`/`disetujui`/`ditolak`).
- CHECK `ck_leave_requests_review_state`: draft = `reviewed_by` dan `reviewed_at` NULL; final = `reviewed_at` wajib. `reviewed_by` boleh NULL setelah akun reviewer dihapus (FK SET NULL), `reviewed_at` tetap bukti respons.
- Batas 09.00 Asia/Jakarta divalidasi Backend; tidak dipasang CHECK agar tidak bergantung zona waktu server.

#### `permission_letters` (022)
- Append-only: `student_id`, `type` (`pulang_tatib`/`dispensasi`), `uploaded_by`, `evidence_file_url`, `note`, `created_at`; tanpa `updated_at`.
- Sesuai PRD, surat hanya lampiran — tidak menulis otomatis ke `student_attendances`.
- FK `student_id` dan `uploaded_by` RESTRICT.

#### `alpha_daily_summaries` + `alpha_warning_logs` (023)
- `alpha_daily_summaries` PK `(student_id, date)`; menyimpan `lesson_total`, `lesson_alpha`, `is_alpha`, snapshot `class_id`/`academic_year_id`.
- CHECK `is_alpha = (lesson_total > 0 AND lesson_alpha * 4 > lesson_total * 3)` — **strictly > 75%**; 6 dari 8 jam bukan Alpha.
- `alpha_warning_logs` adalah event log ambang 3/5/9, **tanpa UNIQUE**. Deviasi dari PRD: unique `(student_id, academic_year_id, threshold)` menghalangi peringatan terpicu ulang setelah akumulasi turun lalu naik.
- Index `(academic_year_id, student_id, is_alpha)` dan `(class_id, date)`; warning `(student_id, academic_year_id, triggered_at DESC)`.

### Permission Epic 3/4 (017)
- 23 permission baru: 17 Epic 3 (`student.*`, `teacher.*`, `class.*`, `subject.*`, `academic_year.*`) + 6 Epic 4 (`schedule.*`).
- Grant mengikuti matriks PRD; total permission menjadi 30 dan `role_permissions` menjadi 61 pada database bersih.

### Permission Epic 5/6 (024)
- 13 permission baru: 8 Epic 5 (`attendance.*`, `leave_request.*`, `permission_letter.upload`) + 5 Epic 6 (`teacher_attendance.*`).
- Total menjadi **43 permission** dan **94 role_permissions** pada database bersih. Cakupan data (kelas sendiri, guru sendiri) tetap divalidasi Backend.

### Trigger
| Trigger | Fungsi |
|---|---|
| `trg_users_normalize` (BEFORE INSERT/UPDATE) | `lower(btrim(email))`, trim `username`/`nisn` — menjamin kepatuhan `CHECK email = lower(email)` |
| `trg_users_updated_at` (BEFORE UPDATE) | auto-set `updated_at` — juga dasar optimistic locking F2.3 |
| `trg_academic_years_updated_at`, `trg_subjects_updated_at`, `trg_teachers_updated_at`, `trg_classes_updated_at`, `trg_students_updated_at`, `trg_schedules_updated_at` (BEFORE UPDATE) | auto-set `updated_at` memakai `fn_set_updated_at` |
| `trg_students_sync_nisn` (AFTER INSERT/UPDATE OF nisn) | sinkron `students.nisn` -> `users.nisn` |
| `trg_users_sync_nisn` (AFTER UPDATE OF nisn) | sinkron `users.nisn` -> `students.nisn`; guard `IS DISTINCT FROM` mencegah rekursi |
| `trg_schedules_bump_version` (BEFORE UPDATE) | `version := version + 1` untuk optimistic locking jadwal |
| `trg_teacher_attendances_updated_at`, `trg_student_attendances_updated_at`, `trg_alpha_daily_summaries_updated_at` (BEFORE UPDATE) | auto-set `updated_at` memakai `fn_set_updated_at` |
| `trg_teacher_attendances_guard` (BEFORE INSERT/UPDATE) | tolak jadwal kegiatan; set status `hadir`/`guru_pengganti` dari perbandingan guru |
| `trg_student_attendances_guard` (BEFORE INSERT/UPDATE) | tolak jadwal kegiatan; isi snapshot kelas/tahun ajaran; kunci snapshot saat UPDATE |
| `trg_student_attendances_bump_version` (BEFORE UPDATE) | `version := version + 1` memakai `fn_bump_version` |

---

## 3. Deviasi / penambahan dari PRD

Baseline = tabel Bagian 8 PRD Epic 1 + Bagian 8 PRD Epic 2 + Bagian 6 PRD Epic 3 + Bagian 6 PRD Epic 4. Semua kolom PRD dipertahankan; berikut **tambahan & perubahan**:

| # | Tabel | Tambahan / Perubahan | Alasan |
|---|---|---|---|
| 1 | `users` | `password_changed_at` | Audit + jejak "kapan password terakhir berubah" |
| 2 | `users` | index `lower(email)` + trigger normalisasi | PRD mewajibkan email case-insensitive; UNIQUE biasa tidak cukup |
| 3 | `otp_codes` | `last_sent_at` | Cooldown resend 60 dtk & batas 5 resend/jam (F1.6) butuh waktu kirim terakhir |
| 4 | `sessions` | `revoked_at` | "Invalidate semua sesi" (F1.4/F1.5) butuh penanda revoke tanpa menghapus baris (audit tetap ada) |
| 5 | `sessions` | `ip_address`, `user_agent`, `last_used_at` | Pelengkap `device_info`, berguna untuk debugging & keamanan |
| 6 | semua | `COMMENT ON ...` | Dokumentasi schema bawaan PostgreSQL |
| 7 | `users` | CHECK `ck_users_password_or_google` **dihapus di `004`** | Epic 1 mewajibkan minimal password ATAU Google; F2.2 membuat akun staf tanpa kredensial — dua aturan tidak bisa hidup berdampingan |
| 8 | `users` | `failed_login_at` (lewat `003_add_failed_login_at.sql`) | PRD 3.B menuntut 5 gagal **dalam 15 menit**; counter tanpa penanda waktu tidak bisa mengukur jendela |
| 9 | `users` | `inactive_reason`, `deactivated_at` + `CHECK ck_users_inactive_state` (lewat `004`) | F2.4 menuntut alasan & waktu penonaktifan tersimpan; CHECK menjaga konsistensi dua arah |
| 10 | `roles` | `label`, `category`, `is_assignable` | F2.5: role assignable vs terkunci & validasi kombinasi (staff/student) dihitung dari DB |
| 11 | `users` | `CHECK ck_users_username_format` dipasang di `004`, lalu **dicabut di `006`** | Unsur username Epic 2 masih ditunda. CHECK 3–30 lowercase bertentangan dengan Epic 1 (registrasi 3–50, case-sensitive); kolom & UNIQUE tetap dipertahankan untuk login |
| 12 | `permissions`, `role_permissions` | 2 tabel baru | F2.7: Matriks Hak Akses baku + otorisasi permission-based |
| 13 | `users` | index `ix_users_name` | Rekomendasi Bagian 8 untuk pencarian daftar akun (F2.1) |
| 14 | `users` | `archived_at` + `CHECK ck_users_archived_state` + partial index (lewat `008`) | Kebutuhan model Backend Epic 2; kolom resmi untuk pengarsipan akun (siswa lulus). Hanya sah saat akun nonaktif, wajib dikosongkan saat reaktivasi |
| 15 | `activity_logs` | 1 tabel baru + 4 index (lewat `007`) | AC Epic 2 menuntut event CUD tercatat. Tabel dimiliki Epic 13; dibuat sekarang sebagai fondasi, tanpa FK agar log tetap utuh setelah akun dihapus |
| 16 | `activity_logs` | `target_type`, `target_id`, index target generik (lewat `009`) | Event Epic 3/4 menargetkan kelas/mapel/tahun ajaran/jadwal, bukan hanya akun |
| 17 | `students`, `teachers` | FK `user_id` **ON DELETE RESTRICT** (PRD Epic 3 menulis CASCADE) | Profil tidak boleh hilang diam-diam; akun hanya dihapus bila tanpa riwayat. Riwayat tetap ditahan FK schedules/absensi |
| 18 | `students` | Trigger sinkron `students.nisn` <-> `users.nisn` | PRD menyimpan NISN di dua tempat; trigger mencegah drift tanpa mengubah alur login Epic 1 |
| 19 | `schedules` | `subject_id` tetap **NOT NULL** saat `schedule_type = 'kegiatan'` (PRD menyebut nullable) | Jurnal Epic 7 tetap membutuhkan mapel; `activity_name` hanya mengganti tampilan |
| 20 | `schedules` | `UNIQUE(teacher_id, schedule_date, start_time)`, exclusion constraint slot bertumpuk, kolom `version` + trigger | PRD hanya mengunci slot kelas; guru double-booking dan lost update tetap mungkin tanpa pengaman ini |
| 21 | `permissions`/`role_permissions` | 23 permission Epic 3/4 + grant matriks (lewat `017`) | Setiap epic wajib menambahkan permission modulnya sendiri |
| 22 | `teacher_attendances` | Trigger penentu `hadir`/`guru_pengganti`, kolom `created_at`, index parsial `schedules` (lewat `019`) | Status tidak boleh dipercaya dari klien; race F6.2/F6.3 butuh UNIQUE + waktu tulis yang jelas |
| 22b | `teacher_attendances` | Nilai `confirmation_method = 'koreksi_admin'` + CHECK longgar untuk koreksi manual (lewat `025`) | F6.4 mengizinkan Admin/Waka mengoreksi status; koreksi tidak punya QR generator, sedangkan CHECK `019` mewajibkannya |
| 23 | `student_attendances` | Snapshot `class_id`, `academic_year_id`, kolom `version` (lewat `020`) | Rekap historis per kelas harus stabil setelah siswa pindah kelas; edit F5.3 butuh optimistic locking |
| 24 | `leave_requests` | `UNIQUE(student_id, date)` penuh, `class_id` snapshot, CHECK pasangan review (lewat `021`) | PRD hanya mengunci saat draft sehingga pengajuan kedua lolos setelah respons; F5.7 butuh kelas saat pengajuan |
| 25 | `alpha_daily_summaries` | Tabel ringkasan harian baru (lewat `023`) | PRD menghitung ulang pada setiap tulis; tanpa ringkasan, audit dan peringatan rawan dihitung ganda |
| 26 | `alpha_warning_logs` | Tanpa UNIQUE `(student_id, academic_year_id, threshold)` (lewat `023`) | Unique PRD menghalangi peringatan terpicu ulang setelah akumulasi turun lalu naik (skenario E1) |
| 27 | `permissions`/`role_permissions` | 13 permission Epic 5/6 + 33 grant (lewat `024`) | Setiap epic wajib menambahkan permission modulnya sendiri |

Tidak ada kolom PRD yang **dihapus**. Kolom `active_role_id` tidak dipasang karena sudah dihapus dari PRD v2.1.

Catatan lintas tim akibat #7 dan #11: Backend **tidak boleh lagi** mengandalkan `ck_users_password_or_google` (boleh membuat akun tanpa kredensial). Untuk username, Epic 2 **tidak boleh** mengandalkan format 3–30 lowercase di DB — validasi Epic 1 tetap 3–50 case-sensitive sampai aturan Epic 2 final.

## 4. Keputusan teknis

| Topik | Keputusan | Alternatif |
|---|---|---|
| Tipe ID | `bigint GENERATED ALWAYS AS IDENTITY` | UUIDv7 bila butuh ID tak tertebak lintas sistem |
| Enum (`purpose`, `inactive_reason`, `category`, `roles.name`) | `VARCHAR + CHECK/UNIQUE` (bukan `CREATE TYPE`) | `CREATE TYPE` — lebih ketat, tapi tiap perubahan = migration ekstra |
| Kredensial awal akun staf (F2.2) | Tanpa password & tanpa Google (`NULL`/`NULL`); login pertama lewat link akun, Google, atau Reset Password | CHECK "minimal satu kredensial" (Epic 1) — tidak kompatibel dengan F2.2, sudah dihapus |
| Case username | Penyimpanan case-**sensitive**, tanpa CHECK format (dicabut di `006`); aturan format Epic 2 ditunda sampai PRD final. Epic 1 tetap 3–50 karakter | Format Epic 2 `^[a-z0-9._]{3,30}$` dikunci di DB — ditolak karena meregresi registrasi Epic 1 |
| Format NISN | 10 digit angka (`^[0-9]{10}$`) | Rentang lebih longgar (`6–20` digit) |
| Otorisasi | **RBAC berbasis permission (Epic 2)**: tabel `permissions` + `role_permissions`, akses = union seluruh role akun, **default deny** di Backend; matriks baku disiapkan seeder | Tanpa tabel permission — pemetaan endpoint→role di kode BE (keputusan Epic 1, digantikan oleh PRD Epic 2) |
| Audit login gagal | Hanya state terkini di `users`: counter + `failed_login_at` + `locked_until` (sesuai PRD) | Tabel `login_attempts` berisi tiap percobaan untuk riwayat login penuh |
| `deleted_at` | Tidak dipakai — nonaktif = `is_active = false` (+ `inactive_reason`, `deactivated_at`); arsip = `archived_at` | Soft delete untuk arsip baris |
| `activity_logs` | Dibuat di Epic 2 sebagai fondasi Epic 13 (tanpa FK, tanpa CHECK `action`) | Menunggu Epic 13 — AC Epic 2 tidak bisa diverifikasi QA; atau logger file — event tidak bisa di-query |
| Aturan kombinasi role & "minimal 1 Admin aktif" | Level aplikasi (transaksi + row lock) — kolom `category`/`is_assignable` menyediakan dasar data, tanpa trigger DB | Constraint trigger DB — kompleks, sulit diuji |
| Pencarian daftar akun (F2.1) | Btree `users(name)` dulu (rekomendasi PRD) | `pg_trgm` GIN untuk `contains` — dipertimbangkan sebagai migrasi berikutnya bila terbukti lambat |
| Sumber NISN (Epic 3) | `students.nisn` = acuan akademik; `users.nisn` = kredensial login; trigger dua arah menjaga keduanya sama | Hanya `users.nisn` (menyimpang dari PRD) atau dua kolom tanpa sinkronisasi (rawan drift) |
| Model kelas (Epic 3) | `students.class_id` saja; riwayat keanggotaan ditunda ke Epic 9/10 | `class_memberships` per tahun ajaran — lebih future-proof, tetapi menyimpang dari PRD dan menambah kompleksitas Epic 3/4 |
| Tahun ajaran aktif | Partial unique index + transaksi aktivasi (Backend memakai row lock/unique violation) | Cek aplikasi saja — race condition dua tahun aktif |
| Kegiatan sekolah (Epic 4) | Tetap pada baris `schedules` (`schedule_type`, `activity_name`); master kegiatan ditunda ke Epic 8 | Tabel `school_activities` sekarang — belum dibutuhkan Epic 4, tetapi Epic 8 perlu normalisasi |
| Slot jadwal | Unique kelas + unique guru + exclusion constraint rentang waktu | Hanya unique kelas (PRD) — guru double-booking dan slot bertumpuk lolos |
| Optimistic locking jadwal | Kolom `version` + trigger kenaikan otomatis; API membandingkan versi | `updated_at` saja — presisi lebih rendah dan rawan tabrakan jam server |
| Mapel saat kegiatan | `subject_id` tetap terisi; `activity_name` untuk tampilan | `subject_id NULL` (PRD) — jurnal kehilangan mapel |
| Zona waktu jadwal | Tanggal lokal + `time` tanpa zona; Backend menetapkan Asia/Jakarta | `timestamptz` untuk jam pelajaran — rawan bergeser saat konversi |
| Identitas sesi absensi | `schedules.id` menjadi identitas sesi; tidak ada `attendance_sessions` | Tabel sesi terpisah — menduplikasi tanggal/kelas/jam yang sudah ada di `schedules` |
| Snapshot kelas absensi | `student_attendances.class_id` + `academic_year_id`; `leave_requests.class_id` | Join ke `students.class_id` saat baca — salah setelah siswa pindah kelas |
| Unik pengajuan izin | `UNIQUE(student_id, date)` penuh | Parsial `status = 'draft'` (PRD) — pengajuan kedua lolos setelah disetujui/ditolak |
| Alpha harian | Tabel `alpha_daily_summaries` + rumus `lesson_alpha * 4 > lesson_total * 3` | Hitung ulang dari absensi setiap permintaan — mahal dan rawan peringatan ganda |
| Peringatan Alpha | Event log tanpa UNIQUE; Backend membandingkan akumulasi sebelum/sesudah tulis | UNIQUE per ambang (PRD) — tidak bisa terpicu ulang setelah koreksi menurunkan akumulasi |
| Gate absensi siswa | Form F5.1 terbuka bila `teacher_attendances.status IN ('hadir','guru_pengganti')`; `tidak_hadir` membuka fallback F5.2 | "Tidak ada baris" — bertentangan dengan F6.3 yang selalu menulis `tidak_hadir` |
| QR/kode 30 detik | Cache TTL (Redis/in-memory), tanpa tabel | Tabel token + cleanup job — PRD eksplisit meminta cache |
| Edit jadwal berabsensi | Backend menolak edit `schedules` yang sudah punya baris absensi | Snapshot mapel/guru di setiap baris absensi — duplikasi lebih besar |

**Status akun:** `active` / `inactive`, dengan alasan & waktu penonaktifan (Epic 2 F2.4). Tidak ada status lain.

---

## 5. Peta arsitektural seluruh sistem

> Ringkasan tingkat tinggi seluruh tabel E-Absensi — acuan agar desain Epic 1 & 2 konsisten dengan arsitektur keseluruhan.

```mermaid
erDiagram
    users ||--o| students           : "profil siswa"
    users ||--o| teachers           : "profil guru"
    academic_years ||--o{ classes   : "memiliki"
    subjects ||--o{ schedules       : "mapel jadwal"
    teachers ||--o{ schedules       : "pengampu jadwal"
    teachers ||--o{ teacher_subjects : "mengampu mapel"
    subjects ||--o{ teacher_subjects : "diampu guru"
    classes ||--o{ class_memberships : "berisi siswa (Epic 9/10)"
    students ||--o{ class_memberships : "anggota"
    classes ||--o{ class_officers   : "siswa inti"
    schedules ||--o| teacher_attendances : "kehadiran guru (Epic 6)"
    schedules ||--o{ student_attendances : "absensi siswa (Epic 5)"
    schedules ||--o{ teaching_journals   : "isian guru (Epic 7)"
    students ||--o{ leave_requests : "izin/sakit (maks 09.00)"
    students ||--o{ permission_letters   : "surat tatib/dispensasi"
    students ||--o{ alpha_daily_summaries : "alpha harian"
    students ||--o{ alpha_warning_logs : "peringatan 3/5/9"
    roles ||--o{ role_permissions : "diberi izin (Epic 2)"
    permissions ||--o{ role_permissions : "kamus izin (Epic 2)"

    academic_years { int id PK "tahun ajaran + semester" }
    subjects        { int id PK "mata pelajaran" }
    classes         { int id PK "kelas + wali kelas" }
    students        { bigint id PK, bigint user_id FK, varchar nisn UK, int class_id FK }
    teachers        { bigint id PK, bigint user_id FK }
    class_memberships { bigint id PK, int class_id FK, bigint student_id FK }
    class_officers  { bigint id PK, int class_id FK, bigint student_id FK, varchar position }
    schedules       { bigint id PK, date schedule_date, time start_time, time end_time, bigint class_id FK, bigint subject_id FK, bigint teacher_id FK, varchar schedule_type, varchar activity_name, bigint created_by FK, int version }
    teacher_subjects { bigint teacher_id PK,FK, bigint subject_id PK,FK }
    school_activities { bigint id PK, date activity_date, varchar name "Epic 8" }
    teacher_attendances { bigint id PK, bigint schedule_id FK,UK, varchar status "hadir|guru_pengganti|tidak_hadir", bigint confirmed_teacher_id FK, varchar confirmation_method, timestamptz confirmed_at, bigint generated_by_user_id FK, varchar generated_by_role }
    student_attendances { bigint id PK, bigint schedule_id FK, bigint student_id FK, bigint class_id FK "snapshot", bigint academic_year_id FK "snapshot", varchar status, varchar source, bigint recorded_by FK, varchar note, int version }
    leave_requests  { bigint id PK, bigint student_id FK, bigint class_id FK "snapshot", varchar type, date date, varchar status, bigint reviewed_by FK }
    permission_letters { bigint id PK, bigint student_id FK, varchar type, bigint uploaded_by FK, varchar evidence_file_url }
    alpha_daily_summaries { bigint student_id PK,FK, date date PK, bigint academic_year_id FK, bigint class_id FK, smallint lesson_total, smallint lesson_alpha, boolean is_alpha }
    alpha_warning_logs { bigint id PK, bigint student_id FK, bigint academic_year_id FK, smallint threshold "3|5|9", smallint alpha_days, timestamptz triggered_at }
    teaching_journals { bigint id PK, bigint schedule_id FK, text materi, text description, boolean submitted }
    notifications   { bigint id PK, bigint user_id FK, text payload, boolean is_read }
    activity_logs   { bigint id PK, bigint actor_user_id, bigint target_user_id, varchar target_type, bigint target_id, varchar action, jsonb snapshot, timestamptz created_at }
    roles           { smallint id PK, varchar name UK, varchar label, varchar category, boolean is_assignable }
    permissions     { bigint id PK, varchar code UK, varchar module }
    role_permissions { smallint role_id PK,FK, bigint permission_id PK,FK }
```

### Catatan arsitektural

1. **`users` vs `students`/`teachers`** — `nisn` tetap ada di `users` karena registrasi siswa (F1.1) menuntut NISN sejak akun dibuat; `students.nisn` menjadi acuan akademik dan disinkronkan trigger. Profil siswa/guru berupa tabel sendiri yang terhubung lewat `user_id` FK → `users`.
2. **Absensi per jam pelajaran** — `schedules.id` menjadi identitas sesi (1 baris = tanggal x kelas x jam), sehingga absensi benar-benar *per mata pelajaran per pertemuan*. Tidak ada `attendance_sessions` terpisah. QR 30 detik hanya ada di cache; kehadiran guru dicatat di `teacher_attendances`, lalu form F5.1 menulis `student_attendances`.
3. **Guru pengganti** — `teacher_attendances.status` berisi `hadir | guru_pengganti | tidak_hadir`. Pengganti dideteksi dari `confirmed_teacher_id <> schedules.teacher_id` (tanpa kolom `substitute_of`), dan status ditentukan trigger agar tidak bisa dikirim klien.
4. **Jadwal berbasis tanggal** — `schedules.schedule_date` + `start_time`/`end_time` (bukan hari-in-a-week). Kegiatan sekolah pada Epic 4 memakai `schedule_type = 'kegiatan'` + `activity_name`; master `school_activities`/`schedule_overrides` disiapkan untuk Epic 8. Slot kelas/guru dijaga unique + exclusion constraint.
5. **Jurnal terpisah dari absensi** — `teaching_journals` tetap ada meski `teacher_attendances.status = 'tidak_hadir'` (PRD KS-18), dengan flag `submitted` untuk menandai "Guru Mapel tidak mengisi jurnal".
6. **Multi-role** — otorisasi seluruh modul dihitung dari union `user_roles`; tidak ada kolom "role aktif" di tabel mana pun.
7. **FK ke `users.id` wajib `ON DELETE RESTRICT`** pada seluruh tabel epic berikutnya — F2.6 hanya mengizinkan penghapusan akun staf yang tidak punya riwayat; cascade hanya berlaku untuk tabel Epic 1 (`user_roles`, `sessions`, `otp_codes`).
8. **`activity_logs`** dimiliki Epic 13, tetapi tabelnya **dibuat di Epic 2** (`007`) sebagai fondasi agar event CUD bisa disimpan dan diverifikasi. Epic 2 menulis 7 event kanonik akun; Epic 3/4 menambah event master data dan jadwal memakai `target_type` + `target_id` generik (`009`). Epic 13 menambah fitur tampilan/filter, bukan membuat ulang tabel. Tanpa FK agar log tetap utuh setelah target dihapus.
9. **Epic 3/4/5/6 sudah fisik di database** — `academic_years`, `subjects`, `teachers`, `classes`, `students`, `teacher_subjects`, `schedules` (`010`-`016`); `teacher_attendances` (`019`); `student_attendances`, `leave_requests`, `permission_letters`, `alpha_daily_summaries`, `alpha_warning_logs` (`020`-`023`). `class_memberships`, `class_officers`, `teaching_journals`, `notifications`, dan `school_activities` masih rencana Epic 7-12.
10. **Absensi menyimpan snapshot** — `student_attendances.class_id`/`academic_year_id` dan `leave_requests.class_id` diisi saat tulis. Rekap per kelas tetap benar setelah siswa pindah kelas, tanpa tabel riwayat keanggotaan yang baru dibuat Epic 9/10.
