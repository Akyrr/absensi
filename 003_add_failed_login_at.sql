-- =============================================================================
-- E-Absensi - 003: Kolom failed_login_at untuk jendela lockout 15 menit
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\003_add_failed_login_at.sql
--
-- Konteks:
--   PRD Epic 1 Bagian 3.B: 5 kali gagal login berturut-turut DALAM 15 MENIT
--   mengakibatkan akun terkunci 15 menit. Skema 001 hanya menyediakan counter
--   failed_login_attempts tanpa penanda waktu, sehingga window 15 menit tidak
--   dapat diukur secara presisi. Kolom ini menyimpan waktu kegagalan terakhir.
--
-- Idempotent: aman dijalankan berulang.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS failed_login_at timestamptz;

COMMENT ON COLUMN users.failed_login_at IS 'Waktu kegagalan login terakhir; dasar jendela 5 percobaan dalam 15 menit (PRD 3.B). NULL bila belum pernah gagal atau setelah window direset.';

COMMIT;
