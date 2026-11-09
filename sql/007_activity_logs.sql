-- =============================================================================
-- E-Absensi - 007: Tabel activity_logs (fondasi Epic 13, event Epic 2)
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\007_activity_logs.sql
--
-- Konteks:
--   PRD Epic 2 mewajibkan setiap operasi CUD menghasilkan event ke Log Aktivitas
--   (AC Epic 2), sedangkan PRD menetapkan tabel log dimiliki Epic 13. Tabel ini
--   dibuat lebih awal di Epic 2 sebagai FONDASI Epic 13: Epic 13 menambah kolom
--   dan fitur tampilan/filter, bukan membuat ulang tabel.
--
-- Isi perubahan:
--   1. Tabel activity_logs: pelaku, target, kode event, snapshot aman, waktu.
--   2. Index: target, action, actor, created_at (semua berpasangan created_at
--      DESC kecuali created_at murni untuk daftar log kronologis).
--   3. COMMENT: kode event kanonik + larangan data sensitif di snapshot.
--
-- Keputusan penting:
--   - actor_user_id dan target_user_id TANPA foreign key. Log dan snapshot
--     harus tetap utuh walau akun pelaku/target dihapus permanen. Nilai NULL
--     pada actor_user_id berarti pelaku sistem (misalnya proses otomatis).
--   - action TANPA CHECK. Daftar event bertambah tiap epic; CHECK akan memaksa
--     migrasi baru setiap kali ada event baru. Kode kanonik didokumentasikan
--     di COMMENT.
--   - snapshot tidak boleh memuat password_hash, google_id, token, atau OTP.
--     Ini tidak bisa ditegakkan DB; wajib diuji di Backend.
--   - Backend menulis log DALAM TRANSAKSI YANG SAMA dengan operasi CUD agar
--     operasi sukses tidak kehilangan event.
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS, COMMENT bersifat replace.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS activity_logs (
    id             bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id  bigint,
    target_user_id bigint,
    action         varchar(50) NOT NULL,
    snapshot       jsonb,
    created_at     timestamptz NOT NULL DEFAULT now()
);

-- "riwayat sebuah akun target"
CREATE INDEX IF NOT EXISTS ix_activity_logs_target
    ON activity_logs (target_user_id, created_at DESC);

-- "semua event bertipe X"
CREATE INDEX IF NOT EXISTS ix_activity_logs_action
    ON activity_logs (action, created_at DESC);

-- "apa saja yang dilakukan pelaku X"
CREATE INDEX IF NOT EXISTS ix_activity_logs_actor
    ON activity_logs (actor_user_id, created_at DESC);

-- daftar log kronologis (tanpa filter target/action/actor)
CREATE INDEX IF NOT EXISTS ix_activity_logs_created_at
    ON activity_logs (created_at DESC);

COMMENT ON TABLE activity_logs IS 'Log aktivitas (fondasi Epic 13, dibuat di Epic 2). Menyimpan pelaku, target, kode event, snapshot aman, dan waktu. Tanpa FK agar log tetap utuh setelah akun pelaku/target dihapus permanen.';
COMMENT ON COLUMN activity_logs.actor_user_id  IS 'Pelaku operasi (id users) tanpa FK. NULL = pelaku sistem/proses otomatis. Tetap tersimpan walau akun pelaku dihapus.';
COMMENT ON COLUMN activity_logs.target_user_id IS 'Akun yang menjadi target operasi (id users) tanpa FK. Tetap tersimpan walau akun target dihapus permanen.';
COMMENT ON COLUMN activity_logs.action         IS 'Kode event kanonik Epic 2: ACCOUNT_CREATED, ACCOUNT_UPDATED, ACCOUNT_DEACTIVATED, ACCOUNT_ACTIVATED, ROLE_ASSIGNED, ROLE_REVOKED, ACCOUNT_DELETED. Epic berikutnya menambah kode sendiri - tidak ada CHECK agar tidak perlu migrasi tiap event baru.';
COMMENT ON COLUMN activity_logs.snapshot       IS 'Snapshot/diff aman untuk audit. DILARANG memuat password_hash, google_id, token, atau OTP.';
COMMENT ON COLUMN activity_logs.created_at     IS 'Waktu event terjadi (default now()).';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas (jalankan manual setelah import):
--   SELECT to_regclass('public.activity_logs');       -- activity_logs
--   SELECT count(*) FROM pg_indexes
--    WHERE tablename = 'activity_logs';               -- 4 index (+ PK)
--   SELECT conname FROM pg_constraint
--    WHERE conrelid = 'activity_logs'::regclass
--      AND contype = 'f';                             -- 0 baris (tanpa FK)
-- =============================================================================
