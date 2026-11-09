-- =============================================================================
-- E-Absensi - 006: Drop CHECK format username (penundaan scope Epic 2)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\006_drop_username_format_check.sql
--
-- Konteks:
--   004 memasang CHECK ck_users_username_format (^[a-z0-9._]{3,30}$) berdasarkan
--   PRD Epic 2 v1.0. Unsur username untuk PRD Epic 2 ditunda sampai aturannya
--   final, sementara Epic 1 tetap memakai username untuk login dan registrasi
--   dengan aturan 3-50 karakter (case-sensitive). CHECK Epic 2 menolak nilai
--   yang sah di Epic 1 (misalnya "Budi" atau username 31+ karakter), sehingga
--   berpotensi meregresi registrasi yang sedang berjalan.
--
-- Isi perubahan:
--   1. users: DROP CONSTRAINT ck_users_username_format.
--
-- Yang TIDAK berubah:
--   - Kolom users.username tetap ada (dipakai login/registrasi Epic 1).
--   - CONSTRAINT uq_users_username tetap ada (username tetap unik).
--   - Tidak ada data yang dihapus.
--
-- Bila format username Epic 2 nanti final, pasang kembali lewat migrasi baru.
--
-- Idempotent: DROP CONSTRAINT IF EXISTS aman dijalankan berulang.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE users DROP CONSTRAINT IF EXISTS ck_users_username_format;

COMMIT;

-- =============================================================================
-- Verifikasi ringkas (jalankan manual setelah import):
--   SELECT conname FROM pg_constraint WHERE conname = 'ck_users_username_format';
--     -- hasil: 0 baris (sudah dihapus)
--   SELECT conname FROM pg_constraint WHERE conname = 'uq_users_username';
--     -- hasil: 1 baris (unique tetap ada)
-- =============================================================================
