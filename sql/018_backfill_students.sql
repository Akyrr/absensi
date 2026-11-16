-- =============================================================================
-- E-Absensi - 018: Backfill students dari akun ber-role siswa
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\018_backfill_students.sql
--
-- Isi perubahan:
--   Membuat baris students untuk akun yang sudah ber-role siswa dan punya
--   NISN, tetapi belum punya profil siswa. class_id dibiarkan NULL.
--
-- Catatan:
--   - Registrasi baru wajib membuat students dalam transaksi yang sama
--     (perubahan Backend, di luar migrasi ini).
--   - Aman dijalankan berulang dan no-op bila belum ada akun siswa.
--   - Akun siswa tanpa NISN dilewati; NISN wajib untuk membuat profil.
--
-- Idempotent: NOT EXISTS + ON CONFLICT (user_id) DO NOTHING.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO students (user_id, nisn)
SELECT u.id, u.nisn
  FROM users u
  JOIN user_roles ur ON ur.user_id = u.id
  JOIN roles r       ON r.id = ur.role_id AND r.name = 'siswa'
 WHERE u.nisn IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM students s WHERE s.user_id = u.id
   )
ON CONFLICT (user_id) DO NOTHING;

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM students;
--   SELECT count(*) FROM users u
--     JOIN user_roles ur ON ur.user_id = u.id
--     JOIN roles r ON r.id = ur.role_id AND r.name = 'siswa'
--    WHERE NOT EXISTS (SELECT 1 FROM students s WHERE s.user_id = u.id);
--   -- hasil kedua: 0 (atau jumlah akun siswa tanpa NISN)
-- =============================================================================
