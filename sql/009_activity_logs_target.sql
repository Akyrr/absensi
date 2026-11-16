-- =============================================================================
-- E-Absensi - 009: Target generik untuk activity_logs
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\009_activity_logs_target.sql
--
-- Konteks:
--   Epic 3/4 mencatat CUD pada kelas, mapel, tahun ajaran, dan jadwal. Target
--   tersebut bukan akun users, sehingga target_user_id saja tidak cukup.
--
-- Isi perubahan:
--   1. Kolom target_type dan target_id (tanpa FK, agar log tetap utuh setelah
--      target dihapus).
--   2. Backfill log lama: target_user_id -> target_type = 'USER', target_id.
--   3. Index untuk filter "semua log untuk target X".
--
-- Kode target_type yang dipakai: USER, STUDENT, TEACHER, CLASS, SUBJECT,
-- ACADEMIC_YEAR, SCHEDULE. Tidak ada CHECK agar Epic berikutnya bisa menambah
-- tipe tanpa migrasi baru; daftar dijaga lewat COMMENT dan Backend.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, UPDATE bersyarat, CREATE INDEX IF NOT
-- EXISTS, COMMENT bersifat replace.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS target_type varchar(20);
ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS target_id   bigint;

-- Log Epic 2 hanya punya target akun. Isi target generik agar filter lama
-- tetap berfungsi setelah kolom baru dipakai.
UPDATE activity_logs
   SET target_type = 'USER',
       target_id   = target_user_id
 WHERE target_user_id IS NOT NULL
   AND target_type IS NULL;

CREATE INDEX IF NOT EXISTS ix_activity_logs_target_entity
    ON activity_logs (target_type, target_id, created_at DESC);

COMMENT ON COLUMN activity_logs.target_type IS 'Tipe target generik: USER, STUDENT, TEACHER, CLASS, SUBJECT, ACADEMIC_YEAR, SCHEDULE. Tanpa CHECK agar mudah bertambah.';
COMMENT ON COLUMN activity_logs.target_id   IS 'ID target sesuai target_type, tanpa FK. Tetap tersimpan walau target dihapus.';
COMMENT ON COLUMN activity_logs.target_user_id IS 'Khusus target akun (Epic 2). Untuk target non-user, gunakan target_type + target_id.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'activity_logs' AND column_name IN ('target_type','target_id');
--   SELECT target_type, count(*) FROM activity_logs GROUP BY target_type;
--   SELECT indexname FROM pg_indexes WHERE tablename = 'activity_logs';
-- =============================================================================
