-- =============================================================================
-- E-Absensi - 014: Tabel students (Epic 3)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\014_students.sql
--
-- Isi perubahan:
--   1. Tabel students: profil siswa, NISN, kelas saat ini.
--   2. UNIQUE user_id dan NISN; CHECK format NISN 10 digit.
--   3. Sinkronisasi dua arah students.nisn <-> users.nisn lewat trigger.
--   4. Trigger updated_at memakai fn_set_updated_at dari 001.
--
-- Catatan:
--   - students.nisn adalah acuan data akademik; users.nisn tetap dipakai
--     Epic 1 untuk login/registrasi. Trigger menjaga keduanya identik.
--   - FK user_id memakai ON DELETE RESTRICT (bukan CASCADE). Profil siswa
--     tidak boleh hilang diam-diam saat akun dihapus.
--   - class_id nullable = "Tanpa Kelas" (PRD F3.1). Riwayat kelas belum
--     dimodelkan di Epic 3; akan ditangani Epic 9/10.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
-- DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS students (
    id         bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint      NOT NULL,
    nisn       varchar(10) NOT NULL,
    class_id   bigint,
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_students_user UNIQUE (user_id),
    CONSTRAINT uq_students_nisn UNIQUE (nisn),
    CONSTRAINT ck_students_nisn_format CHECK (nisn ~ '^[0-9]{10}$'),
    CONSTRAINT fk_students_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_students_class FOREIGN KEY (class_id)
        REFERENCES classes (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_students_class ON students (class_id);

DROP TRIGGER IF EXISTS trg_students_updated_at ON students;
CREATE TRIGGER trg_students_updated_at
    BEFORE UPDATE ON students
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Sinkronisasi NISN. Arah students -> users dipakai saat koreksi Epic 3;
-- arah users -> students menjaga nilai tetap sama bila users diubah lebih dulu
-- (misalnya proses registrasi). Guard IS DISTINCT FROM mencegah rekursi.
CREATE OR REPLACE FUNCTION fn_sync_students_users_nisn() RETURNS trigger AS $$
BEGIN
    IF TG_TABLE_NAME = 'students' THEN
        UPDATE users
           SET nisn = NEW.nisn
         WHERE id = NEW.user_id
           AND nisn IS DISTINCT FROM NEW.nisn;
    ELSE
        UPDATE students
           SET nisn = NEW.nisn
         WHERE user_id = NEW.id
           AND nisn IS DISTINCT FROM NEW.nisn;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_students_sync_nisn ON students;
CREATE TRIGGER trg_students_sync_nisn
    AFTER INSERT OR UPDATE OF nisn ON students
    FOR EACH ROW EXECUTE FUNCTION fn_sync_students_users_nisn();

DROP TRIGGER IF EXISTS trg_users_sync_nisn ON users;
CREATE TRIGGER trg_users_sync_nisn
    AFTER UPDATE OF nisn ON users
    FOR EACH ROW EXECUTE FUNCTION fn_sync_students_users_nisn();

COMMENT ON TABLE  students         IS 'Profil siswa (Epic 3 F3.1). Dibuat otomatis saat registrasi Epic 1.';
COMMENT ON COLUMN students.user_id  IS 'Akun siswa; unik. FK RESTRICT agar profil tidak hilang saat akun dihapus.';
COMMENT ON COLUMN students.nisn     IS 'NISN 10 digit, unik. Disinkronkan dengan users.nisn lewat trigger.';
COMMENT ON COLUMN students.class_id IS 'Kelas saat ini; NULL = Tanpa Kelas. FK RESTRICT.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM students;                  -- 0
--   SELECT tgname FROM pg_trigger
--    WHERE tgrelid IN ('students'::regclass, 'users'::regclass)
--      AND NOT tgisinternal;
-- =============================================================================
