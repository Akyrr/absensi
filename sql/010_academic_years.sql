-- =============================================================================
-- E-Absensi - 010: Tabel academic_years (Epic 3)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\010_academic_years.sql
--
-- Isi perubahan:
--   1. Tabel academic_years: nama, semester aktif, rentang tanggal, status.
--   2. Partial unique index: maksimal satu baris is_active = true.
--   3. Trigger updated_at memakai fn_set_updated_at dari 001.
--
-- Catatan:
--   - Aktivasi tahun ajaran harus dilakukan dalam transaksi yang juga
--     menonaktifkan tahun lama. Index mencegah dua baris aktif; Backend wajib
--     menangani unique violation sebagai 409 Conflict.
--   - end_date boleh NULL selama tahun ajaran belum ditutup.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS academic_years (
    id              bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            varchar(20) NOT NULL,
    active_semester varchar(12) NOT NULL,
    start_date      date        NOT NULL,
    end_date        date,
    is_active       boolean     NOT NULL DEFAULT false,
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_academic_years_name UNIQUE (name),
    CONSTRAINT ck_academic_years_semester
        CHECK (active_semester IN ('semester_1', 'semester_2')),
    CONSTRAINT ck_academic_years_dates
        CHECK (end_date IS NULL OR end_date >= start_date)
);

-- Hanya satu baris boleh aktif. Nilai true yang sama pada banyak baris akan
-- melanggar unique index ini.
CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_years_active
    ON academic_years (is_active)
    WHERE is_active;

DROP TRIGGER IF EXISTS trg_academic_years_updated_at ON academic_years;
CREATE TRIGGER trg_academic_years_updated_at
    BEFORE UPDATE ON academic_years
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE  academic_years                 IS 'Tahun ajaran dan semester aktif (Epic 3 F3.5). Maksimal satu baris is_active = true.';
COMMENT ON COLUMN academic_years.name            IS 'Nama tahun ajaran, contoh 2026/2027. Unik.';
COMMENT ON COLUMN academic_years.active_semester IS 'Semester yang sedang berjalan: semester_1 atau semester_2.';
COMMENT ON COLUMN academic_years.start_date      IS 'Tanggal mulai tahun ajaran.';
COMMENT ON COLUMN academic_years.end_date        IS 'Tanggal selesai; NULL selama belum ditutup.';
COMMENT ON COLUMN academic_years.is_active       IS 'true = tahun ajaran aktif. Dijaga partial unique index.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM academic_years;                 -- 0
--   SELECT indexdef FROM pg_indexes
--    WHERE indexname = 'uq_academic_years_active';
-- =============================================================================
