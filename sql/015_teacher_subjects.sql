-- =============================================================================
-- E-Absensi - 015: Tabel teacher_subjects (Epic 3)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\015_teacher_subjects.sql
--
-- Isi perubahan:
--   1. Tabel pivot teacher_subjects: mapel yang diampu seorang guru.
--   2. Primary key gabungan (teacher_id, subject_id).
--   3. FK teacher_id CASCADE, subject_id RESTRICT.
--
-- Catatan:
--   - CASCADE pada teacher_id aman karena penghapusan profil guru tetap
--     ditahan FK schedules.teacher_id (RESTRICT) bila guru sudah punya jadwal.
--   - Mapel yang masih diampu tidak boleh dihapus (RESTRICT).
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS teacher_subjects (
    teacher_id bigint      NOT NULL,
    subject_id bigint      NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_teacher_subjects PRIMARY KEY (teacher_id, subject_id),
    CONSTRAINT fk_teacher_subjects_teacher FOREIGN KEY (teacher_id)
        REFERENCES teachers (id) ON DELETE CASCADE,
    CONSTRAINT fk_teacher_subjects_subject FOREIGN KEY (subject_id)
        REFERENCES subjects (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_teacher_subjects_subject ON teacher_subjects (subject_id);

COMMENT ON TABLE  teacher_subjects            IS 'Mapel yang diampu guru (Epic 3 F3.2/F3.4).';
COMMENT ON COLUMN teacher_subjects.teacher_id IS 'Guru pengampu; CASCADE bila profil guru dihapus.';
COMMENT ON COLUMN teacher_subjects.subject_id IS 'Mapel yang diampu; RESTRICT selama masih dipakai.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM teacher_subjects;          -- 0
--   SELECT conname FROM pg_constraint
--    WHERE conrelid = 'teacher_subjects'::regclass;
-- =============================================================================
