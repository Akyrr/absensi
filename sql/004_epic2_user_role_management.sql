-- =============================================================================
-- E-Absensi - 004: Epic 2 User & Role Management
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\004_epic2_user_role_management.sql
--
-- Sumber requirement: PRD EPIC 2 v1.0 (F2.4, F2.5, F2.7 + Bagian 8)
--
-- Isi perubahan:
--   1. users: kolom status nonaktif (inactive_reason, deactivated_at) + CHECK.
--   2. users: DROP ck_users_password_or_google - bentrok dengan F2.2 (akun staf
--      dibuat tanpa password dan tanpa Google; kredensial diatur kemudian).
--   3. users: CHECK format username (3-30 karakter huruf kecil, angka, titik,
--      underscore) sesuai PRD 7.C / 9.B.
--   4. roles: metadata role (label, category, is_assignable) untuk validasi
--      F2.5 dihitung dari DB.
--   5. Tabel baru permissions & role_permissions (F2.7 RBAC, matriks hak akses).
--   6. Seed 7 permission Epic 2 + grant ke role admin.
--   7. Index users(name) untuk pencarian daftar akun (F2.1).
--
-- Idempotent: aman dijalankan berulang.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. users - status nonaktif (F2.4) + relaksasi kredensial + format username
-- -----------------------------------------------------------------------------

-- F2.2 membuat akun staf tanpa password dan tanpa Google - CHECK Epic 1
-- (minimal satu kredensial harus ada) tidak berlaku lagi.
ALTER TABLE users DROP CONSTRAINT IF EXISTS ck_users_password_or_google;

ALTER TABLE users ADD COLUMN IF NOT EXISTS inactive_reason varchar(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS deactivated_at  timestamptz;

-- Alasan penonaktifan: hanya 3 nilai enum PRD (tetap VARCHAR + CHECK, bukan CREATE TYPE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'users'::regclass AND conname = 'ck_users_inactive_reason'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT ck_users_inactive_reason
            CHECK (inactive_reason IS NULL
                   OR inactive_reason IN ('graduated', 'transferred', 'other'));
    END IF;
END $$;

-- Konsistensi status dua arah: aktif = alasan & waktu kosong; nonaktif = keduanya terisi.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'users'::regclass AND conname = 'ck_users_inactive_state'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT ck_users_inactive_state
            CHECK (
                (is_active = true
                 AND inactive_reason IS NULL AND deactivated_at IS NULL)
                OR
                (is_active = false
                 AND inactive_reason IS NOT NULL AND deactivated_at IS NOT NULL)
            );
    END IF;
END $$;

-- Format username PRD 7.C: 3-30 karakter, huruf kecil/angka/titik/underscore.
-- DB menolak pelanggaran; validasi ramah- pengguna ada di Backend (harus lowercase).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'users'::regclass AND conname = 'ck_users_username_format'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT ck_users_username_format
            CHECK (username IS NULL OR username ~ '^[a-z0-9._]{3,30}$');
    END IF;
END $$;

COMMENT ON COLUMN users.inactive_reason IS 'Alasan penonaktifan akun (F2.4): graduated=lulus, transferred=pindah, other=lainnya. NULL selama akun aktif.';
COMMENT ON COLUMN users.deactivated_at  IS 'Waktu akun dinonaktifkan (F2.4). NULL selama akun aktif. Diisi oleh Admin lewat PATCH /users/{id}/status.';

-- -----------------------------------------------------------------------------
-- 2. roles - metadata role untuk F2.5 & tampilan (label, category, is_assignable)
-- -----------------------------------------------------------------------------

ALTER TABLE roles ADD COLUMN IF NOT EXISTS label         varchar(100);
ALTER TABLE roles ADD COLUMN IF NOT EXISTS category      varchar(10);
ALTER TABLE roles ADD COLUMN IF NOT EXISTS is_assignable boolean NOT NULL DEFAULT false;

-- Backfill 7 role seed (idempotent - seluruh role yang diketahui tercakup).
UPDATE roles r
   SET label         = v.label,
       category      = v.category,
       is_assignable = v.is_assignable
  FROM (VALUES
        ('admin',          'Admin / Staf Kurikulum', 'staff',   true),
        ('waka_kurikulum', 'Waka Kurikulum',         'staff',   true),
        ('waka_kesiswaan', 'Waka Kesiswaan',         'staff',   true),
        ('guru_mapel',     'Guru Mata Pelajaran',    'staff',   true),
        ('wali_kelas',     'Wali Kelas',             'staff',   false),
        ('siswa_inti',     'Siswa Inti',             'student', false),
        ('siswa',          'Siswa',                  'student', false)
       ) AS v(name, label, category, is_assignable)
 WHERE r.name = v.name;

ALTER TABLE roles ALTER COLUMN label    SET NOT NULL;
ALTER TABLE roles ALTER COLUMN category SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'roles'::regclass AND conname = 'ck_roles_category'
    ) THEN
        ALTER TABLE roles ADD CONSTRAINT ck_roles_category
            CHECK (category IN ('staff', 'student'));
    END IF;
END $$;

COMMENT ON COLUMN roles.label         IS 'Nama tampilan role untuk UI Admin (F2.2/F2.5).';
COMMENT ON COLUMN roles.category      IS 'Kelompok role: staff atau student. Dasar validasi kombinasi role (misalnya staff dan siswa tidak boleh bercampur).';
COMMENT ON COLUMN roles.is_assignable IS 'true bila role boleh diberikan/dicabut Admin lewat F2.5 (admin, waka_kurikulum, waka_kesiswaan, guru_mapel). Role terkunci (wali_kelas, siswa_inti, siswa) = false.';

-- -----------------------------------------------------------------------------
-- 3. permissions - kamus izin sistem (F2.7). Setiap epic menambahkan permission
--    modulnya ke tabel ini lewat file migrasi masing-masing.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS permissions (
    id          bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        varchar(100) NOT NULL,
    module      varchar(50)  NOT NULL,
    description varchar(255),

    CONSTRAINT uq_permissions_code UNIQUE (code)
);

COMMENT ON TABLE  permissions         IS 'Kamus izin sistem (RBAC F2.7). Kode unik berformat module.action, contoh: account.view. Epic berikutnya menambahkan permission modulnya sendiri.';
COMMENT ON COLUMN permissions.code        IS 'Kode izin unik, format: module.action (huruf kecil, titik). Dipakai Backend pada middleware requirePermission.';
COMMENT ON COLUMN permissions.module      IS 'Modul terkait (account, role, permission, dst.) - dasar pengelompokan Matriks Hak Akses.';
COMMENT ON COLUMN permissions.description IS 'Deskripsi human-readable untuk Matriks Hak Akses di UI Admin.';

-- -----------------------------------------------------------------------------
-- 4. role_permissions - pemberian izin per role (F2.7). PRD Epic 2 Bagian 11:
--    matriks hak akses baku, disiapkan sistem (seeder), tidak diubah lewat UI.
-- -----------------------------------------------------------------------------

-- role_id sengaja RESTRICT: role master tidak boleh terhapus selama izinnya terpasang.
-- permission_id CASCADE: permission dicabut = pemberiannya ikut hilang.
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id       smallint NOT NULL,
    permission_id bigint   NOT NULL,

    CONSTRAINT pk_role_permissions PRIMARY KEY (role_id, permission_id),
    CONSTRAINT fk_role_permissions_role       FOREIGN KEY (role_id)
        REFERENCES roles (id)       ON DELETE RESTRICT,
    CONSTRAINT fk_role_permissions_permission FOREIGN KEY (permission_id)
        REFERENCES permissions (id) ON DELETE CASCADE
);

-- "izini apa saja milik role ini" & "role mana saja yang punya izin ini"
CREATE INDEX IF NOT EXISTS ix_role_permissions_permission ON role_permissions (permission_id);

COMMENT ON TABLE  role_permissions            IS 'Pemberian permission ke role sesuai Matriks Hak Akses Baku (PRD Bagian 11). Bersifat tetap - diubah lewat migrasi/seeder, bukan lewat UI.';
COMMENT ON COLUMN role_permissions.role_id       IS 'Role penerima izin (FK ke roles, ON DELETE RESTRICT).';
COMMENT ON COLUMN role_permissions.permission_id IS 'Permission yang diberikan (FK ke permissions, ON DELETE CASCADE).';

-- -----------------------------------------------------------------------------
-- 5. Seed permission Epic 2 (7 baris) - seluruhnya untuk role admin
--    (PRD F2.7: Matriks Hak Akses, halaman dan endpoint hanya Admin).
-- -----------------------------------------------------------------------------
INSERT INTO permissions (code, module, description) VALUES
    ('account.view',       'account',     'Melihat daftar dan detail akun'),
    ('account.create',     'account',     'Menambah akun staf'),
    ('account.update',     'account',     'Mengubah data akun'),
    ('account.set_status', 'account',     'Mengaktifkan atau menonaktifkan akun'),
    ('account.delete',     'account',     'Menghapus akun staf tanpa riwayat'),
    ('role.assign',        'role',        'Memberi atau mencabut role akun'),
    ('permission.view',    'permission',  'Melihat matriks hak akses')
ON CONFLICT (code)
DO UPDATE SET module      = EXCLUDED.module,
              description = EXCLUDED.description;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM roles r
 CROSS JOIN permissions p
 WHERE r.name = 'admin'
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 6. Index pencarian daftar akun (F2.1 menyaring berdasarkan nama)
--    Index btree sesuai rekomendasi PRD Bagian 8. Pencarian contains (%q%)
--    tidak memakai index ini; bila perlu, pertimbangkan pg_trgm sebagai 005.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_users_name ON users (name);

COMMIT;

-- =============================================================================
-- Verifikasi ringkas (jalankan manual setelah import):
--   SELECT count(*) FROM permissions;    -- 7
--   SELECT count(*) FROM role_permissions; -- 7 (semua milik admin)
--   SELECT name, label, category, is_assignable FROM roles ORDER BY id;
--   SELECT code, module FROM permissions ORDER BY code;
--   SELECT conname FROM pg_constraint WHERE conname = 'ck_users_password_or_google';
--     -- hasil: 0 baris (sudah dihapus)
-- =============================================================================
