-- =============================================================================
-- E-Absensi - 002: Akses database untuk team + encoding default koneksi
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\002_access_and_encoding.sql
--
-- Konfigurasi:
--   1. Akses isi database dibuka untuk semua role melalui grant ke PUBLIC.
--   2. Default encoding koneksi = UTF8.
--
-- Idempotent: file ini aman dijalankan berulang (GRANT/ALTER tidak error jika
-- kondisinya sudah terpenuhi).
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- BAGIAN A - Akses "semua role" via PUBLIC
-- PUBLIC = pseudo-role yang mencakup semua role, termasuk role yang dibuat kemudian.
-- -----------------------------------------------------------------------------

-- 1. Izin koneksi ke database (secara default sudah ada; dinyatakan eksplisit).
--    Pernyataan level database memakai current_database() agar berlaku pada
--    nama database apa pun.
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO PUBLIC', current_database());
END $$;

-- 2. Izin memakai (dan membuat objek di) skema public
GRANT USAGE, CREATE ON SCHEMA public TO PUBLIC;

-- 3. Hak pada objek yang SUDAH ADA (5 tabel + 5 sequence di Epic 1)
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON ALL TABLES IN SCHEMA public TO PUBLIC;

--    Tanpa USAGE pada sequence, INSERT ke kolom "id ... IDENTITY" akan gagal:
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO PUBLIC;

-- 4. Hak pada objek yang dibuat kemudian - otomatis lewat ALTER DEFAULT
--    PRIVILEGES, tanpa perlu GRANT tambahan.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO PUBLIC;

-- -----------------------------------------------------------------------------
-- BAGIAN B - Default encoding koneksi
-- Berlaku untuk koneksi BARU yang tidak menentukan encoding sendiri.
-- CATATAN: koneksi yang menyetel env PGCLIENTENCODING tetap memakai nilai
-- tersebut; kosongkan env itu (set PGCLIENTENCODING=) bila ditemukan.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET client_encoding TO ''UTF8''', current_database());
END $$;

COMMIT;

-- =============================================================================
-- Verifikasi (jalankan manual setelah import):
--   SHOW client_encoding;                       -- hasil: UTF8
--   SELECT * FROM pg_default_acl;                -- harus terisi 2 baris
--   SELECT grantee, privilege_type FROM information_schema.table_privileges
--     WHERE table_schema='public' AND table_name='users' ORDER BY grantee;
-- =============================================================================
