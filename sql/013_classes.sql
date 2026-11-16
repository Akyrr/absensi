-- =============================================================================
-- E-Absensi - 013: Tabel classes (Epic 3)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\013_classes.sql
--
-- Isi perubahan:
--   1. Tabel classes: nama kelas unik per tahun ajaran, tingkat, wali kelas.
--   2. FK academic_year_id RESTRICT; wali_kelas_user_id SET NULL.
--   3. Index academic_year_id dan is_active.
--   4. Trigger updated_at memakai fn_set_updated_at dari 001.
--
-- Catatan:
--   - wali_kelas_user_id menunjuk users.id (bukan teachers.id), sesuai PRD
--     Epic 3. Pengisiannya menjadi kewenangan Epic 9.
--   - Nama kelas tidak unik global; unik hanya di dalam satu tahun ajaran.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS classes (
    id                  bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                varchar(50) NOT NULL,
    grade_level         smallint    NOT NULL,
    academic_year_id    bigint      NOT NULL,
    wali_kelas_user_id  bigint,
    is_active           boolean     NOT NULL DEFAULT true,
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_classes_name_year UNIQUE (name, academic_year_id),
    CONSTRAINT ck_classes_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT ck_classes_grade_level CHECK (grade_level IN (10, 11, 12)),
    CONSTRAINT fk_classes_academic_year FOREIGN KEY (academic_year_id)
        REFERENCES academic_years (id) ON DELETE RESTRICT,
    CONSTRAINT fk_classes_wali_kelas FOREIGN KEY (wali_kelas_user_id)
        REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_classes_academic_year ON classes (academic_year_id);
CREATE INDEX IF NOT EXISTS ix_classes_active          ON classes (is_active);

DROP TRIGGER IF EXISTS trg_classes_updated_at ON classes;
CREATE TRIGGER trg_classes_updated_at
    BEFORE UPDATE ON classes
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE  classes                    IS 'Master kelas per tahun ajaran (Epic 3 F3.3).';
COMMENT ON COLUMN classes.name               IS 'Nama kelas, contoh X RPL 1. Unik per academic_year_id.';
COMMENT ON COLUMN classes.grade_level        IS 'Tingkat kelas: 10, 11, atau 12.';
COMMENT ON COLUMN classes.academic_year_id   IS 'Tahun ajaran pemilik kelas.';
COMMENT ON COLUMN classes.wali_kelas_user_id IS 'Akun wali kelas; diisi Epic 9, read-only di Epic 3.';
COMMENT ON COLUMN classes.is_active          IS 'false = kelas dinonaktifkan; hapus permanen hanya jika belum dipakai.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM classes;                   -- 0
--   SELECT indexname FROM pg_indexes WHERE tablename = 'classes';
-- =============================================================================
