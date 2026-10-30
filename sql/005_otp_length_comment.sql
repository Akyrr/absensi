-- =============================================================================
-- E-Absensi - 005: Komentar otp_codes - panjang OTP 6 karakter
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\005_otp_length_comment.sql
--
-- Konteks:
--   Panjang kode OTP diubah dari 8 menjadi 6 karakter. Tidak ada perubahan
--   struktur tabel - kode OTP disimpan sebagai hash (code_hash), sehingga
--   panjang asli tidak memengaruhi kolom. File ini hanya menyinkronkan
--   COMMENT ON TABLE yang masih menyebut 8 karakter (di 001).
--
-- Idempotent: aman dijalankan berulang (COMMENT ON bersifat replace).
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

COMMENT ON TABLE otp_codes IS 'Kode OTP (hash, 6 karakter huruf besar+angka). Terisolasi per purpose: change_password tidak bisa dipakai di reset_password.';

COMMIT;
