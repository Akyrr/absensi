-- =============================================================================
-- E-Absensi - 016: Tabel schedules (Epic 4)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\016_schedules.sql
--
-- Isi perubahan:
--   1. Tabel schedules: satu baris = satu kejadian pada satu tanggal.
--   2. UNIQUE(class_id, schedule_date, start_time) untuk slot kelas.
--   3. UNIQUE(teacher_id, schedule_date, start_time) untuk slot guru.
--   4. Exclusion constraint: slot kelas/guru tidak boleh bertumpuk.
--   5. version + trigger untuk optimistic locking.
--   6. Index filter per tanggal, guru, kelas, dan tipe.
--
-- Penyimpangan yang disengaja dari PRD:
--   - subject_id NOT NULL juga saat schedule_type = 'kegiatan', agar jurnal
--     tetap punya mapel. activity_name dipakai untuk tampilan kegiatan.
--   - Ada UNIQUE guru dan exclusion constraint, karena UNIQUE kelas saja
--     tidak mencegah guru mengajar ganda.
--   - Ada kolom version; PRD hanya menyebut updated_at.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, CREATE EXTENSION IF NOT,
-- DROP TRIGGER IF EXISTS, ALTER TABLE ... ADD CONSTRAINT dicek lewat
-- pg_constraint.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Dibutuhkan exclusion constraint untuk kombinasi bigint/date + range.
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS schedules (
    id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_date date        NOT NULL,
    start_time    time        NOT NULL,
    end_time      time        NOT NULL,
    class_id      bigint      NOT NULL,
    subject_id    bigint      NOT NULL,
    teacher_id    bigint      NOT NULL,
    schedule_type varchar(10) NOT NULL DEFAULT 'pelajaran',
    activity_name varchar(150),
    created_by    bigint,
    version       integer     NOT NULL DEFAULT 1,
    updated_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_schedules_class_slot
        UNIQUE (class_id, schedule_date, start_time),
    CONSTRAINT uq_schedules_teacher_slot
        UNIQUE (teacher_id, schedule_date, start_time),
    CONSTRAINT ck_schedules_time_order CHECK (end_time > start_time),
    CONSTRAINT ck_schedules_type
        CHECK (schedule_type IN ('pelajaran', 'kegiatan')),
    CONSTRAINT ck_schedules_version CHECK (version > 0),
    CONSTRAINT ck_schedules_activity
        CHECK (
            (schedule_type = 'pelajaran' AND activity_name IS NULL)
            OR
            (schedule_type = 'kegiatan'
             AND activity_name IS NOT NULL
             AND btrim(activity_name) <> '')
        ),
    CONSTRAINT fk_schedules_class FOREIGN KEY (class_id)
        REFERENCES classes (id) ON DELETE RESTRICT,
    CONSTRAINT fk_schedules_subject FOREIGN KEY (subject_id)
        REFERENCES subjects (id) ON DELETE RESTRICT,
    CONSTRAINT fk_schedules_teacher FOREIGN KEY (teacher_id)
        REFERENCES teachers (id) ON DELETE RESTRICT,
    CONSTRAINT fk_schedules_created_by FOREIGN KEY (created_by)
        REFERENCES users (id) ON DELETE SET NULL
);

-- Slot bertumpuk (bukan hanya jam mulai yang sama) ditolak di level DB.
-- Rentang memakai tanggal + jam sehingga aman untuk jadwal lintas hari.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'schedules'::regclass
           AND conname = 'ex_schedules_class_overlap'
    ) THEN
        ALTER TABLE schedules ADD CONSTRAINT ex_schedules_class_overlap
            EXCLUDE USING gist (
                class_id WITH =,
                (tsrange(schedule_date + start_time, schedule_date + end_time)) WITH &&
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'schedules'::regclass
           AND conname = 'ex_schedules_teacher_overlap'
    ) THEN
        ALTER TABLE schedules ADD CONSTRAINT ex_schedules_teacher_overlap
            EXCLUDE USING gist (
                teacher_id WITH =,
                (tsrange(schedule_date + start_time, schedule_date + end_time)) WITH &&
            );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_schedules_date         ON schedules (schedule_date);
CREATE INDEX IF NOT EXISTS ix_schedules_teacher_date ON schedules (teacher_id, schedule_date);
CREATE INDEX IF NOT EXISTS ix_schedules_class_date   ON schedules (class_id, schedule_date);
CREATE INDEX IF NOT EXISTS ix_schedules_type         ON schedules (schedule_type);

DROP TRIGGER IF EXISTS trg_schedules_updated_at ON schedules;
CREATE TRIGGER trg_schedules_updated_at
    BEFORE UPDATE ON schedules
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- version naik otomatis pada setiap UPDATE. Backend cukup mengirim
-- expected version di WHERE dan menolak 0 baris sebagai 409 Conflict.
CREATE OR REPLACE FUNCTION fn_schedules_bump_version() RETURNS trigger AS $$
BEGIN
    NEW.version := OLD.version + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_schedules_bump_version ON schedules;
CREATE TRIGGER trg_schedules_bump_version
    BEFORE UPDATE ON schedules
    FOR EACH ROW EXECUTE FUNCTION fn_schedules_bump_version();

COMMENT ON TABLE  schedules                IS 'Jadwal per tanggal (Epic 4), bukan pola mingguan. Satu baris = satu kejadian.';
COMMENT ON COLUMN schedules.schedule_date  IS 'Tanggal pelaksanaan jadwal.';
COMMENT ON COLUMN schedules.start_time     IS 'Jam mulai lokal sekolah.';
COMMENT ON COLUMN schedules.end_time       IS 'Jam selesai; wajib lebih besar dari start_time.';
COMMENT ON COLUMN schedules.class_id       IS 'Kelas yang dijadwalkan; FK RESTRICT.';
COMMENT ON COLUMN schedules.subject_id     IS 'Mapel; tetap terisi saat kegiatan agar jurnal punya mapel. FK RESTRICT.';
COMMENT ON COLUMN schedules.teacher_id     IS 'Guru pengampu; tetap terisi saat kegiatan. FK RESTRICT.';
COMMENT ON COLUMN schedules.schedule_type  IS 'pelajaran atau kegiatan.';
COMMENT ON COLUMN schedules.activity_name  IS 'Nama kegiatan bebas; wajib saat kegiatan, NULL saat pelajaran.';
COMMENT ON COLUMN schedules.created_by     IS 'Akun Admin pembuat/importir; SET NULL bila akun dihapus.';
COMMENT ON COLUMN schedules.version        IS 'Versi optimistic locking; naik otomatis setiap UPDATE.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM schedules;                 -- 0
--   SELECT conname, contype FROM pg_constraint
--    WHERE conrelid = 'schedules'::regclass ORDER BY conname;
--   SELECT indexname FROM pg_indexes WHERE tablename = 'schedules';
-- =============================================================================
