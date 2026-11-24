-- =============================================================================
-- E-Absensi - 019: Tabel teacher_attendances (Epic 6)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\019_teacher_attendances.sql
--
-- Isi perubahan:
--   1. Tabel teacher_attendances: satu baris = satu jadwal pelajaran.
--   2. UNIQUE(schedule_id) mencegah dua baris kehadiran untuk jadwal sama.
--   3. CHECK status/metode/role + pasangan kolom konfirmasi.
--   4. Trigger: tolak jadwal kegiatan; status hadir/guru_pengganti ditentukan
--      dari perbandingan confirmed_teacher_id dengan schedules.teacher_id.
--   5. Index filter status/guru + index parsial schedules untuk job F6.3.
--
-- Catatan:
--   - F6.3 menulis tidak_hadir dengan INSERT ... ON CONFLICT (schedule_id)
--     DO NOTHING. UNIQUE(schedule_id) menjadi penentu pemenang saat job dan
--     scan guru berjalan bersamaan.
--   - QR/kode cadangan TTL 30 detik TIDAK disimpan di tabel ini (cache).
--   - Koreksi Admin/Waka ke tidak_hadir wajib mengosongkan confirmed_teacher_id,
--     confirmation_method, confirmed_at, generated_by_user_id, generated_by_role
--     agar CHECK pasangan terpenuhi.
--   - Jadwal yang sudah punya baris kehadiran tidak boleh diubah gurunya.
--     Backend menolak edit schedules bila teacher_attendances/student_attendances
--     sudah ada untuk schedule_id tersebut.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
-- DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS teacher_attendances (
    id                       bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_id              bigint      NOT NULL,
    status                   varchar(20) NOT NULL,
    confirmed_teacher_id     bigint,
    confirmation_method      varchar(20),
    confirmed_at             timestamptz,
    generated_by_user_id     bigint,
    generated_by_role        varchar(20),
    keterangan               text,
    keterangan_updated_by    bigint,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_teacher_attendances_schedule UNIQUE (schedule_id),
    CONSTRAINT ck_teacher_attendances_status
        CHECK (status IN ('hadir', 'guru_pengganti', 'tidak_hadir')),
    CONSTRAINT ck_teacher_attendances_method
        CHECK (confirmation_method IS NULL
               OR confirmation_method IN ('qr_scan', 'kode_cadangan')),
    CONSTRAINT ck_teacher_attendances_generated_role
        CHECK (generated_by_role IS NULL
               OR generated_by_role IN ('siswa_inti', 'wali_kelas')),
    CONSTRAINT ck_teacher_attendances_confirmed
        CHECK (
            (status = 'tidak_hadir'
             AND confirmed_teacher_id IS NULL
             AND confirmation_method IS NULL
             AND confirmed_at IS NULL
             AND generated_by_user_id IS NULL
             AND generated_by_role IS NULL)
            OR
            (status IN ('hadir', 'guru_pengganti')
             AND confirmed_teacher_id IS NOT NULL
             AND confirmation_method IS NOT NULL
             AND confirmed_at IS NOT NULL
             AND generated_by_user_id IS NOT NULL
             AND generated_by_role IS NOT NULL)
        ),
    CONSTRAINT fk_teacher_attendances_schedule FOREIGN KEY (schedule_id)
        REFERENCES schedules (id) ON DELETE RESTRICT,
    CONSTRAINT fk_teacher_attendances_teacher FOREIGN KEY (confirmed_teacher_id)
        REFERENCES teachers (id) ON DELETE RESTRICT,
    CONSTRAINT fk_teacher_attendances_generated_by FOREIGN KEY (generated_by_user_id)
        REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_teacher_attendances_keterangan_by FOREIGN KEY (keterangan_updated_by)
        REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_teacher_attendances_status
    ON teacher_attendances (status);
CREATE INDEX IF NOT EXISTS ix_teacher_attendances_confirmed_teacher
    ON teacher_attendances (confirmed_teacher_id);

-- Job F6.3 mencari jadwal pelajaran yang end_time-nya sudah lewat.
CREATE INDEX IF NOT EXISTS ix_schedules_lesson_end
    ON schedules (schedule_date, end_time)
    WHERE schedule_type = 'pelajaran';

DROP TRIGGER IF EXISTS trg_teacher_attendances_updated_at ON teacher_attendances;
CREATE TRIGGER trg_teacher_attendances_updated_at
    BEFORE UPDATE ON teacher_attendances
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Status ditentukan server, bukan klien:
--   confirmed_teacher_id = schedules.teacher_id  -> hadir
--   confirmed_teacher_id <> schedules.teacher_id -> guru_pengganti
-- Trigger juga menolak absensi guru pada jadwal kegiatan.
CREATE OR REPLACE FUNCTION fn_teacher_attendances_guard() RETURNS trigger AS $$
DECLARE
    v_teacher_id bigint;
    v_type       varchar(10);
BEGIN
    SELECT teacher_id, schedule_type
      INTO v_teacher_id, v_type
      FROM schedules
     WHERE id = NEW.schedule_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Jadwal % tidak ditemukan', NEW.schedule_id;
    END IF;

    IF v_type <> 'pelajaran' THEN
        RAISE EXCEPTION 'Kehadiran guru hanya untuk jadwal pelajaran (schedule_id=%)',
            NEW.schedule_id;
    END IF;

    IF NEW.status IN ('hadir', 'guru_pengganti') THEN
        IF NEW.confirmed_teacher_id IS NULL THEN
            RAISE EXCEPTION 'confirmed_teacher_id wajib untuk status %', NEW.status;
        END IF;

        IF NEW.confirmed_teacher_id = v_teacher_id THEN
            NEW.status := 'hadir';
        ELSE
            NEW.status := 'guru_pengganti';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_teacher_attendances_guard ON teacher_attendances;
CREATE TRIGGER trg_teacher_attendances_guard
    BEFORE INSERT OR UPDATE ON teacher_attendances
    FOR EACH ROW EXECUTE FUNCTION fn_teacher_attendances_guard();

COMMENT ON TABLE  teacher_attendances IS 'Kehadiran guru per jadwal (Epic 6). Satu baris per schedule_id; status ditentukan server.';
COMMENT ON COLUMN teacher_attendances.schedule_id IS 'Jadwal yang dikonfirmasi; unik dan wajib bertipe pelajaran. FK RESTRICT.';
COMMENT ON COLUMN teacher_attendances.status IS 'hadir, guru_pengganti, atau tidak_hadir. Diisi trigger dari perbandingan guru.';
COMMENT ON COLUMN teacher_attendances.confirmed_teacher_id IS 'Guru yang scan/input kode; NULL saat tidak_hadir. FK RESTRICT.';
COMMENT ON COLUMN teacher_attendances.confirmation_method IS 'qr_scan atau kode_cadangan; NULL saat tidak_hadir.';
COMMENT ON COLUMN teacher_attendances.confirmed_at IS 'Waktu konfirmasi berhasil; NULL saat tidak_hadir.';
COMMENT ON COLUMN teacher_attendances.generated_by_user_id IS 'Siswa Inti/Wali Kelas pembuat QR; NULL saat tidak_hadir. SET NULL bila akun dihapus.';
COMMENT ON COLUMN teacher_attendances.generated_by_role IS 'Role pembuat QR saat itu: siswa_inti atau wali_kelas.';
COMMENT ON COLUMN teacher_attendances.keterangan IS 'Anotasi bebas Admin/Waka Kurikulum (F6.4).';
COMMENT ON COLUMN teacher_attendances.keterangan_updated_by IS 'Admin/Waka terakhir yang mengubah keterangan. SET NULL bila akun dihapus.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM teacher_attendances;                 -- 0
--   SELECT conname, contype FROM pg_constraint
--    WHERE conrelid = 'teacher_attendances'::regclass ORDER BY conname;
--   SELECT indexname FROM pg_indexes
--    WHERE tablename IN ('teacher_attendances', 'schedules')
--      AND indexname IN ('ix_teacher_attendances_status',
--                        'ix_teacher_attendances_confirmed_teacher',
--                        'ix_schedules_lesson_end');
-- =============================================================================
