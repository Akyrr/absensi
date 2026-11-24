-- =============================================================================
-- E-Absensi - 025: Dukung koreksi status kehadiran guru oleh Admin/Waka
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\025_teacher_attendance_correction.sql
--
-- Konteks:
--   019 mengunci status hadir/guru_pengganti agar selalu punya method QR atau
--   kode cadangan. F6.4 mengizinkan Admin/Waka mengoreksi status secara manual
--   (mis. tidak_hadir -> hadir saat QR gagal). Koreksi seperti itu tidak punya
--   QR generator, sehingga CHECK lama menolak koreksi yang sah.
--
-- Isi perubahan:
--   1. confirmation_method menerima nilai koreksi_admin.
--   2. Status hadir/guru_pengganti hasil koreksi boleh tanpa generated_by_*.
--   3. Konfirmasi normal (qr_scan/kode_cadangan) tetap wajib punya generator.
--
-- Idempotent: DROP CONSTRAINT IF EXISTS + ADD CONSTRAINT.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE teacher_attendances
    DROP CONSTRAINT IF EXISTS ck_teacher_attendances_method;

ALTER TABLE teacher_attendances
    ADD CONSTRAINT ck_teacher_attendances_method
    CHECK (confirmation_method IS NULL
           OR confirmation_method IN ('qr_scan', 'kode_cadangan', 'koreksi_admin'));

ALTER TABLE teacher_attendances
    DROP CONSTRAINT IF EXISTS ck_teacher_attendances_confirmed;

ALTER TABLE teacher_attendances
    ADD CONSTRAINT ck_teacher_attendances_confirmed
    CHECK (
        (status = 'tidak_hadir'
         AND confirmed_teacher_id IS NULL
         AND confirmation_method IS NULL
         AND confirmed_at IS NULL
         AND generated_by_user_id IS NULL
         AND generated_by_role IS NULL)
        OR
        (status IN ('hadir', 'guru_pengganti')
         AND confirmed_teacher_id IS NOT NULL
         AND confirmation_method IS NOT NULL
         AND confirmed_at IS NOT NULL
         AND (
             (confirmation_method IN ('qr_scan', 'kode_cadangan')
              AND generated_by_user_id IS NOT NULL
              AND generated_by_role IS NOT NULL)
             OR
             (confirmation_method = 'koreksi_admin'
              AND generated_by_user_id IS NULL
              AND generated_by_role IS NULL)
         ))
    );

COMMENT ON COLUMN teacher_attendances.confirmation_method IS
    'qr_scan, kode_cadangan, atau koreksi_admin (F6.4). NULL saat tidak_hadir.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT conname, pg_get_constraintdef(oid)
--     FROM pg_constraint
--    WHERE conrelid = 'teacher_attendances'::regclass
--      AND conname IN ('ck_teacher_attendances_method',
--                      'ck_teacher_attendances_confirmed');
-- =============================================================================
