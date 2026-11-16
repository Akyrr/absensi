-- =============================================================================
-- E-Absensi - 011: Tabel subjects (Epic 3)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\011_subjects.sql
--
-- Isi perubahan:
--   1. Tabel subjects: kode unik, nama, status aktif.
--   2. Index is_active untuk filter daftar mapel.
--   3. Trigger updated_at memakai fn_set_updated_at dari 001.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS subjects (
    id         bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code       varchar(20)  NOT NULL,
    name       varchar(100) NOT NULL,
    is_active  boolean      NOT NULL DEFAULT true,
    updated_at timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT uq_subjects_code UNIQUE (code),
    CONSTRAINT ck_subjects_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT ck_subjects_name_not_blank CHECK (btrim(name) <> '')
);

CREATE INDEX IF NOT EXISTS ix_subjects_active ON subjects (is_active);

DROP TRIGGER IF EXISTS trg_subjects_updated_at ON subjects;
CREATE TRIGGER trg_subjects_updated_at
    BEFORE UPDATE ON subjects
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE  subjects            IS 'Master mata pelajaran (Epic 3 F3.4).';
COMMENT ON COLUMN subjects.code       IS 'Kode mapel unik, contoh MTK-10.';
COMMENT ON COLUMN subjects.name       IS 'Nama tampilan mapel, contoh Matematika.';
COMMENT ON COLUMN subjects.is_active  IS 'false = dinonaktifkan; tidak boleh dihapus jika sudah dipakai jadwal/jurnal.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM subjects;                  -- 0
--   SELECT conname FROM pg_constraint
--    WHERE conrelid = 'subjects'::regclass AND contype = 'u';
-- =============================================================================
