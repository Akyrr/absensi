-- =============================================================================
-- E-Absensi - 023: Tabel alpha harian & log peringatan (Epic 5 F5.10)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\023_alpha_tracking.sql
--
-- Isi perubahan:
--   1. alpha_daily_summaries: hasil hitung Alpha per siswa per tanggal.
--   2. alpha_warning_logs: riwayat peringatan ambang 3/5/9 (tanpa UNIQUE).
--   3. CHECK is_alpha konsisten dengan proporsi jam Alpha (> 75%).
--   4. Index rekap tahun ajaran dan dashboard kelas.
--
-- Penyimpangan yang disengaja dari PRD:
--   - PRD menaruh UNIQUE(student_id, academic_year_id, threshold) pada
--     alpha_warning_logs. Unique itu menghalangi peringatan terpicu ulang
--     setelah akumulasi turun lalu naik kembali (skenario E1). Tabel ini
--     diperlakukan sebagai event log: satu baris per kejadian.
--   - Ada tabel ringkasan harian agar audit dan peringatan tidak dihitung
--     ulang dari nol pada setiap tulis.
--
-- Rumus: is_alpha = lesson_total > 0 AND lesson_alpha * 4 > lesson_total * 3
-- (strictly lebih dari 75 persen; 6 dari 8 jam tidak dihitung Alpha).
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
-- DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS alpha_daily_summaries (
    student_id        bigint      NOT NULL,
    date              date        NOT NULL,
    academic_year_id  bigint      NOT NULL,
    class_id          bigint      NOT NULL,
    lesson_total      smallint    NOT NULL,
    lesson_alpha      smallint    NOT NULL,
    is_alpha          boolean     NOT NULL,
    updated_at        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_alpha_daily_summaries PRIMARY KEY (student_id, date),
    CONSTRAINT ck_alpha_daily_summaries_counts
        CHECK (lesson_total >= 0
               AND lesson_alpha >= 0
               AND lesson_alpha <= lesson_total),
    CONSTRAINT ck_alpha_daily_summaries_is_alpha
        CHECK (is_alpha = (lesson_total > 0
                           AND lesson_alpha * 4 > lesson_total * 3)),
    CONSTRAINT fk_alpha_daily_summaries_student FOREIGN KEY (student_id)
        REFERENCES students (id) ON DELETE RESTRICT,
    CONSTRAINT fk_alpha_daily_summaries_year FOREIGN KEY (academic_year_id)
        REFERENCES academic_years (id) ON DELETE RESTRICT,
    CONSTRAINT fk_alpha_daily_summaries_class FOREIGN KEY (class_id)
        REFERENCES classes (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_alpha_daily_summaries_year
    ON alpha_daily_summaries (academic_year_id, student_id, is_alpha);
CREATE INDEX IF NOT EXISTS ix_alpha_daily_summaries_class_date
    ON alpha_daily_summaries (class_id, date);

DROP TRIGGER IF EXISTS trg_alpha_daily_summaries_updated_at ON alpha_daily_summaries;
CREATE TRIGGER trg_alpha_daily_summaries_updated_at
    BEFORE UPDATE ON alpha_daily_summaries
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE IF NOT EXISTS alpha_warning_logs (
    id                bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id        bigint      NOT NULL,
    academic_year_id  bigint      NOT NULL,
    threshold         smallint    NOT NULL,
    alpha_days        smallint    NOT NULL,
    triggered_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ck_alpha_warning_logs_threshold
        CHECK (threshold IN (3, 5, 9)),
    CONSTRAINT ck_alpha_warning_logs_days
        CHECK (alpha_days >= threshold),
    CONSTRAINT fk_alpha_warning_logs_student FOREIGN KEY (student_id)
        REFERENCES students (id) ON DELETE RESTRICT,
    CONSTRAINT fk_alpha_warning_logs_year FOREIGN KEY (academic_year_id)
        REFERENCES academic_years (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_alpha_warning_logs_student_year
    ON alpha_warning_logs (student_id, academic_year_id, triggered_at DESC);

COMMENT ON TABLE  alpha_daily_summaries IS 'Ringkasan Alpha per siswa per tanggal (Epic 5 F5.10); dihitung ulang setiap absensi tanggal itu berubah.';
COMMENT ON COLUMN alpha_daily_summaries.lesson_total IS 'Jumlah jam pelajaran terjadwal kelas pada tanggal itu.';
COMMENT ON COLUMN alpha_daily_summaries.lesson_alpha IS 'Jumlah jam pelajaran berstatus alpha untuk siswa tersebut.';
COMMENT ON COLUMN alpha_daily_summaries.is_alpha IS 'true bila lesson_alpha * 4 > lesson_total * 3 dan lesson_total > 0.';
COMMENT ON TABLE  alpha_warning_logs IS 'Event log peringatan Alpha 3/5/9 per tahun ajaran. Tanpa UNIQUE agar bisa terpicu ulang.';
COMMENT ON COLUMN alpha_warning_logs.threshold IS 'Ambang hari Alpha: 3, 5, atau 9.';
COMMENT ON COLUMN alpha_warning_logs.alpha_days IS 'Akumulasi hari Alpha saat peringatan terpicu.';
COMMENT ON COLUMN alpha_warning_logs.triggered_at IS 'Waktu peringatan terpicu.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM alpha_daily_summaries;               -- 0
--   SELECT count(*) FROM alpha_warning_logs;                  -- 0
--   SELECT conname, contype FROM pg_constraint
--    WHERE conrelid IN ('alpha_daily_summaries'::regclass,
--                       'alpha_warning_logs'::regclass)
--    ORDER BY conrelid::regclass::text, conname;
-- =============================================================================
