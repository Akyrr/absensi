-- =============================================================================
-- E-Absensi - 022: Tabel permission_letters (Epic 5 F5.8)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\022_permission_letters.sql
--
-- Isi perubahan:
--   1. Tabel permission_letters: surat pulang tatib / dispensasi.
--   2. Tabel append-only, tanpa updated_at dan tanpa fitur ubah.
--   3. FK student_id dan uploaded_by ON DELETE RESTRICT.
--   4. Index riwayat per siswa dan per jenis.
--
-- Catatan:
--   - Sesuai PRD, surat hanya lampiran: TIDAK menulis otomatis ke
--     student_attendances dan tidak mengubah status kehadiran.
--   - uploaded_by wajib Siswa Inti (validasi permission di Backend).
--   - URL file disimpan apa adanya; validasi tipe/ukuran di storage/Backend.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS permission_letters (
    id                 bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id         bigint        NOT NULL,
    type               varchar(20)   NOT NULL,
    uploaded_by        bigint        NOT NULL,
    evidence_file_url  varchar(1000) NOT NULL,
    note               varchar(500),
    created_at         timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT ck_permission_letters_type
        CHECK (type IN ('pulang_tatib', 'dispensasi')),
    CONSTRAINT ck_permission_letters_evidence
        CHECK (btrim(evidence_file_url) <> ''),
    CONSTRAINT fk_permission_letters_student FOREIGN KEY (student_id)
        REFERENCES students (id) ON DELETE RESTRICT,
    CONSTRAINT fk_permission_letters_uploaded_by FOREIGN KEY (uploaded_by)
        REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_permission_letters_student_created
    ON permission_letters (student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_permission_letters_type_created
    ON permission_letters (type, created_at DESC);

COMMENT ON TABLE  permission_letters IS 'Surat pulang tatib/dispensasi (Epic 5 F5.8). Append-only, tidak mengubah absensi otomatis.';
COMMENT ON COLUMN permission_letters.student_id IS 'Siswa yang disebutkan surat. FK RESTRICT.';
COMMENT ON COLUMN permission_letters.type IS 'pulang_tatib atau dispensasi.';
COMMENT ON COLUMN permission_letters.uploaded_by IS 'Siswa Inti pengunggah. FK RESTRICT.';
COMMENT ON COLUMN permission_letters.evidence_file_url IS 'URL file surat; wajib.';
COMMENT ON COLUMN permission_letters.note IS 'Catatan opsional pengunggah.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM permission_letters;                  -- 0
--   SELECT conname, contype FROM pg_constraint
--    WHERE conrelid = 'permission_letters'::regclass ORDER BY conname;
--   SELECT indexname FROM pg_indexes WHERE tablename = 'permission_letters';
-- =============================================================================
