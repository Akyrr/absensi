-- =============================================================================
-- E-Absensi - 020: Tabel student_attendances (Epic 5)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\020_student_attendances.sql
--
-- Isi perubahan:
--   1. Tabel student_attendances: satu baris = satu siswa pada satu jadwal.
--   2. UNIQUE(schedule_id, student_id).
--   3. Snapshot class_id + academic_year_id diisi trigger dari schedules/classes.
--   4. Trigger menolak jadwal kegiatan dan mengunci snapshot pada UPDATE.
--   5. version + updated_at untuk optimistic locking F5.3.
--   6. Index untuk rekap per siswa/kelas dan hitung Alpha.
--
-- Catatan:
--   - Hanya jadwal schedule_type = 'pelajaran' yang boleh punya absensi siswa.
--     Jadwal kegiatan tidak dinilai Alpha.
--   - class_id snapshot = kelas jadwal (schedules.class_id), bukan kelas siswa
--     saat ini. Rekap historis tetap benar setelah siswa pindah kelas.
--   - recorded_by = penulis terakhir dan NOT NULL; FK RESTRICT agar baris
--     absensi tidak kehilangan pelaku. F2.6 sudah melarang hapus akun berriwayat.
--   - F5.7 menimpa baris lewat ON CONFLICT (schedule_id, student_id)
--     DO UPDATE, hanya untuk jadwal pelajaran pada tanggal pengajuan.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
-- DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS student_attendances (
    id                bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_id       bigint      NOT NULL,
    student_id        bigint      NOT NULL,
    class_id          bigint      NOT NULL,
    academic_year_id  bigint      NOT NULL,
    status            varchar(12) NOT NULL,
    source            varchar(24) NOT NULL,
    recorded_by       bigint      NOT NULL,
    note              varchar(500),
    version           integer     NOT NULL DEFAULT 1,
    updated_at        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_student_attendances_schedule_student
        UNIQUE (schedule_id, student_id),
    CONSTRAINT ck_student_attendances_status
        CHECK (status IN ('hadir', 'izin', 'sakit', 'alpha', 'dispensasi')),
    CONSTRAINT ck_student_attendances_source
        CHECK (source IN ('ceklis_guru', 'fallback_wali_kelas',
                          'auto_from_leave_request', 'manual_edit')),
    CONSTRAINT ck_student_attendances_version CHECK (version > 0),
    CONSTRAINT fk_student_attendances_schedule FOREIGN KEY (schedule_id)
        REFERENCES schedules (id) ON DELETE RESTRICT,
    CONSTRAINT fk_student_attendances_student FOREIGN KEY (student_id)
        REFERENCES students (id) ON DELETE RESTRICT,
    CONSTRAINT fk_student_attendances_class FOREIGN KEY (class_id)
        REFERENCES classes (id) ON DELETE RESTRICT,
    CONSTRAINT fk_student_attendances_academic_year FOREIGN KEY (academic_year_id)
        REFERENCES academic_years (id) ON DELETE RESTRICT,
    CONSTRAINT fk_student_attendances_recorded_by FOREIGN KEY (recorded_by)
        REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_student_attendances_student_class
    ON student_attendances (student_id, class_id);
CREATE INDEX IF NOT EXISTS ix_student_attendances_class_student
    ON student_attendances (class_id, student_id);
CREATE INDEX IF NOT EXISTS ix_student_attendances_student_status
    ON student_attendances (student_id, status);

DROP TRIGGER IF EXISTS trg_student_attendances_updated_at ON student_attendances;
CREATE TRIGGER trg_student_attendances_updated_at
    BEFORE UPDATE ON student_attendances
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Snapshot kelas/tahun ajaran diambil dari jadwal, bukan dari input klien.
-- UPDATE tidak boleh mengubah identitas baris atau snapshot.
CREATE OR REPLACE FUNCTION fn_student_attendances_guard() RETURNS trigger AS $$
DECLARE
    v_type             varchar(10);
    v_class_id         bigint;
    v_academic_year_id bigint;
BEGIN
    SELECT s.schedule_type, s.class_id, c.academic_year_id
      INTO v_type, v_class_id, v_academic_year_id
      FROM schedules s
      JOIN classes c ON c.id = s.class_id
     WHERE s.id = NEW.schedule_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Jadwal % tidak ditemukan', NEW.schedule_id;
    END IF;

    IF v_type <> 'pelajaran' THEN
        RAISE EXCEPTION 'Absensi siswa hanya untuk jadwal pelajaran (schedule_id=%)',
            NEW.schedule_id;
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.class_id := v_class_id;
        NEW.academic_year_id := v_academic_year_id;
    ELSIF NEW.schedule_id IS DISTINCT FROM OLD.schedule_id
       OR NEW.student_id IS DISTINCT FROM OLD.student_id
       OR NEW.class_id IS DISTINCT FROM OLD.class_id
       OR NEW.academic_year_id IS DISTINCT FROM OLD.academic_year_id THEN
        RAISE EXCEPTION 'Identitas dan snapshot absensi tidak boleh diubah';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_student_attendances_guard ON student_attendances;
CREATE TRIGGER trg_student_attendances_guard
    BEFORE INSERT OR UPDATE ON student_attendances
    FOR EACH ROW EXECUTE FUNCTION fn_student_attendances_guard();

CREATE OR REPLACE FUNCTION fn_bump_version() RETURNS trigger AS $$
BEGIN
    NEW.version := OLD.version + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_student_attendances_bump_version ON student_attendances;
CREATE TRIGGER trg_student_attendances_bump_version
    BEFORE UPDATE ON student_attendances
    FOR EACH ROW EXECUTE FUNCTION fn_bump_version();

COMMENT ON TABLE  student_attendances IS 'Absensi siswa per jadwal (Epic 5). Hanya untuk jadwal pelajaran; satu baris per siswa per jadwal.';
COMMENT ON COLUMN student_attendances.schedule_id IS 'Jadwal pelajaran terkait. FK RESTRICT; unik bersama student_id.';
COMMENT ON COLUMN student_attendances.student_id IS 'Siswa yang dinilai. FK RESTRICT.';
COMMENT ON COLUMN student_attendances.class_id IS 'Snapshot kelas jadwal; diisi trigger, tidak boleh diubah. FK RESTRICT.';
COMMENT ON COLUMN student_attendances.academic_year_id IS 'Snapshot tahun ajaran kelas; diisi trigger untuk rekap dan Alpha. FK RESTRICT.';
COMMENT ON COLUMN student_attendances.status IS 'hadir, izin, sakit, alpha, atau dispensasi.';
COMMENT ON COLUMN student_attendances.source IS 'ceklis_guru, fallback_wali_kelas, auto_from_leave_request, atau manual_edit.';
COMMENT ON COLUMN student_attendances.recorded_by IS 'Penulis terakhir (Guru/Wali Kelas/Admin/Waka). NOT NULL, FK RESTRICT.';
COMMENT ON COLUMN student_attendances.note IS 'Catatan koreksi manual F5.3; dipertahankan saat F5.7 menimpa status.';
COMMENT ON COLUMN student_attendances.version IS 'Optimistic locking F5.3; naik otomatis setiap UPDATE.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM student_attendances;                 -- 0
--   SELECT conname, contype FROM pg_constraint
--    WHERE conrelid = 'student_attendances'::regclass ORDER BY conname;
--   SELECT indexname FROM pg_indexes WHERE tablename = 'student_attendances';
-- =============================================================================
