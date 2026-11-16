-- =============================================================================
-- E-Absensi - 012: Tabel teachers (Epic 3)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\012_teachers.sql
--
-- Isi perubahan:
--   1. Tabel teachers: profil guru terhubung ke users.
--   2. UNIQUE user_id: satu akun guru hanya punya satu profil.
--   3. Index NIP untuk pencarian.
--   4. Trigger updated_at memakai fn_set_updated_at dari 001.
--
-- Catatan:
--   - FK user_id memakai ON DELETE RESTRICT, bukan CASCADE. Akun yang punya
--     profil guru tidak boleh terhapus diam-diam; Epic 2 F2.6 hanya
--     mengizinkan hapus akun tanpa riwayat.
--   - Validasi role guru_mapel dilakukan Backend, karena role berada di
--     user_roles dan tidak bisa dicek dengan CHECK sederhana.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, DROP TRIGGER IF EXISTS.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS teachers (
    id         bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint      NOT NULL,
    nip        varchar(30) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_teachers_user UNIQUE (user_id),
    CONSTRAINT ck_teachers_nip_not_blank CHECK (btrim(nip) <> ''),
    CONSTRAINT fk_teachers_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_teachers_nip ON teachers (nip);

DROP TRIGGER IF EXISTS trg_teachers_updated_at ON teachers;
CREATE TRIGGER trg_teachers_updated_at
    BEFORE UPDATE ON teachers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE  teachers         IS 'Profil guru (Epic 3 F3.2), terhubung satu-satu ke akun users.';
COMMENT ON COLUMN teachers.user_id  IS 'Akun guru; unik dan wajib ber-role guru_mapel (divalidasi Backend).';
COMMENT ON COLUMN teachers.nip      IS 'Nomor induk tenaga pengajar internal sekolah. Tidak harus unik.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM teachers;                  -- 0
--   SELECT conname FROM pg_constraint
--    WHERE conrelid = 'teachers'::regclass AND contype = 'f';
-- =============================================================================
