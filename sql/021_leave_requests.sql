-- =============================================================================
-- E-Absensi - 021: Tabel leave_requests (Epic 5)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\021_leave_requests.sql
--
-- Isi perubahan:
--   1. Tabel leave_requests: pengajuan izin/sakit satu hari per siswa.
--   2. UNIQUE(student_id, date) penuh, bukan parsial status = 'draft'.
--   3. Snapshot class_id saat pengajuan untuk F5.7 dan rekap historis.
--   4. CHECK pasangan status <-> reviewed_at.
--   5. Index dashboard Wali Kelas.
--
-- Penyimpangan yang disengaja dari PRD:
--   - UNIQUE penuh: setelah pengajuan disetujui/ditolak, siswa tidak boleh
--     mengajukan lagi pada tanggal yang sama. PRD hanya mengunci saat draft,
--     sehingga pengajuan kedua lolos setelah ada respons.
--   - Ada class_id snapshot; PRD tidak menyimpannya, tetapi F5.7 menulis massal
--     per kelas dan siswa bisa pindah kelas setelah tanggal pengajuan.
--   - reviewed_by boleh NULL setelah akun reviewer dihapus (FK SET NULL).
--     Keberadaan reviewed_at tetap menjadi bukti pengajuan sudah direspons.
--
-- Catatan:
--   - Batas pukul 09.00 waktu Asia/Jakarta divalidasi Backend, bukan CHECK,
--     karena bergantung zona waktu sekolah dan jam server.
--   - reason dan evidence_file_url wajib (PRD: keterangan + 1 file bukti).
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS leave_requests (
    id                 bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id         bigint       NOT NULL,
    class_id           bigint       NOT NULL,
    type               varchar(10)  NOT NULL,
    date               date         NOT NULL,
    reason             varchar(500) NOT NULL,
    evidence_file_url  varchar(1000) NOT NULL,
    status             varchar(12)  NOT NULL DEFAULT 'draft',
    reviewed_by        bigint,
    reviewed_at        timestamptz,
    created_at         timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT uq_leave_requests_student_date UNIQUE (student_id, date),
    CONSTRAINT ck_leave_requests_type
        CHECK (type IN ('izin', 'sakit')),
    CONSTRAINT ck_leave_requests_status
        CHECK (status IN ('draft', 'disetujui', 'ditolak')),
    CONSTRAINT ck_leave_requests_reason
        CHECK (btrim(reason) <> ''),
    CONSTRAINT ck_leave_requests_evidence
        CHECK (btrim(evidence_file_url) <> ''),
    CONSTRAINT ck_leave_requests_review_state
        CHECK (
            (status = 'draft'
             AND reviewed_by IS NULL
             AND reviewed_at IS NULL)
            OR
            (status IN ('disetujui', 'ditolak')
             AND reviewed_at IS NOT NULL)
        ),
    CONSTRAINT fk_leave_requests_student FOREIGN KEY (student_id)
        REFERENCES students (id) ON DELETE RESTRICT,
    CONSTRAINT fk_leave_requests_class FOREIGN KEY (class_id)
        REFERENCES classes (id) ON DELETE RESTRICT,
    CONSTRAINT fk_leave_requests_reviewed_by FOREIGN KEY (reviewed_by)
        REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_leave_requests_status_date
    ON leave_requests (status, date);
CREATE INDEX IF NOT EXISTS ix_leave_requests_class_date
    ON leave_requests (class_id, date);

COMMENT ON TABLE  leave_requests IS 'Pengajuan izin/sakit siswa satu hari (Epic 5 F5.6). Satu baris per siswa per tanggal.';
COMMENT ON COLUMN leave_requests.student_id IS 'Siswa pengaju. FK RESTRICT.';
COMMENT ON COLUMN leave_requests.class_id IS 'Snapshot kelas saat pengajuan; dipakai F5.7 menulis absensi. FK RESTRICT.';
COMMENT ON COLUMN leave_requests.type IS 'izin atau sakit.';
COMMENT ON COLUMN leave_requests.date IS 'Tanggal yang diajukan; unik bersama student_id.';
COMMENT ON COLUMN leave_requests.reason IS 'Keterangan dari siswa; wajib tidak kosong.';
COMMENT ON COLUMN leave_requests.evidence_file_url IS 'URL file bukti; wajib. Validasi tipe/ukuran di Backend/storage.';
COMMENT ON COLUMN leave_requests.status IS 'draft (menunggu respons), disetujui, atau ditolak.';
COMMENT ON COLUMN leave_requests.reviewed_by IS 'Wali Kelas yang merespons; SET NULL bila akun dihapus.';
COMMENT ON COLUMN leave_requests.reviewed_at IS 'Waktu respons; wajib terisi untuk status final.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM leave_requests;                      -- 0
--   SELECT conname, contype FROM pg_constraint
--    WHERE conrelid = 'leave_requests'::regclass ORDER BY conname;
--   SELECT indexname FROM pg_indexes WHERE tablename = 'leave_requests';
-- =============================================================================
