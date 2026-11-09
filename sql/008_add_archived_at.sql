-- =============================================================================
-- E-Absensi - 008: Kolom users.archived_at (pengarsipan akun)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\008_add_archived_at.sql
--
-- Konteks:
--   Backend Epic 2 memakai field ArchivedAt *time.Time pada model User. Kolom
--   ini belum ada di 001-004 sehingga query GORM akan gagal setelah model
--   di-update. Pengarsipan otomatis siswa lulus (Next Semester) berasal dari
--   epic berikutnya, tetapi kolomnya disiapkan sekarang agar model konsisten.
--
-- Isi perubahan:
--   1. users: kolom archived_at timestamptz NULL.
--   2. CHECK ck_users_archived_state: arsip hanya sah untuk akun nonaktif.
--   3. Partial index ix_users_archived untuk akun yang sudah diarsipkan.
--   4. COMMENT kolom.
--
-- Aturan pakai (ditegakkan aplikasi + CHECK yang ada):
--   - archived_at hanya boleh diisi saat is_active = false.
--   - Saat mengisi archived_at, Backend WAJIB juga mengisi inactive_reason dan
--     deactivated_at dalam UPDATE yang sama; ck_users_inactive_state (004)
--     menolak is_active = false tanpa keduanya.
--   - Saat mengaktifkan kembali akun, archived_at WAJIB dikosongkan (NULL).
--   - Tidak ada CHECK inactive_reason = 'graduated': arsip bisa dipakai untuk
--     alasan lain di masa depan; aturan "arsip hanya untuk lulusan" cukup di
--     aplikasi.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, CHECK via guard, CREATE INDEX IF NOT
-- EXISTS, COMMENT bersifat replace.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE users ADD COLUMN IF NOT EXISTS archived_at timestamptz;

-- Arsip hanya sah untuk akun yang sudah nonaktif.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'users'::regclass AND conname = 'ck_users_archived_state'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT ck_users_archived_state
            CHECK (archived_at IS NULL OR is_active = false);
    END IF;
END $$;

-- Hanya akun terarsip yang di-index - jumlahnya kecil dibanding seluruh users.
CREATE INDEX IF NOT EXISTS ix_users_archived
    ON users (archived_at) WHERE archived_at IS NOT NULL;

COMMENT ON COLUMN users.archived_at IS 'Waktu akun diarsipkan (misalnya siswa lulus). NULL = belum diarsipkan. Hanya boleh terisi saat is_active = false dan wajib dikosongkan saat akun diaktifkan kembali.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas (jalankan manual setelah import):
--   SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_name = 'users' AND column_name = 'archived_at';
--   SELECT conname FROM pg_constraint WHERE conname = 'ck_users_archived_state';
--   SELECT indexname FROM pg_indexes
--    WHERE tablename = 'users' AND indexname = 'ix_users_archived';
-- =============================================================================
