-- =============================================================================
-- E-Absensi - Sistem Informasi Absensi dan Jurnal Mengajar
-- Epic 1: Authentication & Account Management
-- PostgreSQL DDL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f 001_epic1_auth.sql
--
-- Sumber requirement: PRD Utama (revisi 3) + PRD EPIC 1 v2.1 (Bagian 3, 6, 8)
-- Catatan: seluruh perubahan schema dibungkus BEGIN/COMMIT - gagal = rollback.
--
-- IDEMPOTENT: file ini aman dijalankan berulang - tabel/index yang sudah ada
-- dilewati (CREATE ... IF NOT EXISTS), seed memakai ON CONFLICT DO NOTHING,
-- dan trigger dibuat ulang (DROP IF EXISTS). Perubahan skema dikerjakan lewat
-- file migration terpisah.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. roles - master 7 role sistem (referensi tetap / seed data)
--    Kunci PRD EPIC 1 Bagian 2. role wali_kelas & siswa_inti adalah role
--    TAMBAHAN pada akun yang sudah ada (bukan akun terpisah), tetap berdiri
--    sendiri sebagai baris di sini (didukung oleh user_roles yang many-to-many).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS roles (
    id          smallint     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        varchar(50)  NOT NULL,
    description varchar(255),
    created_at  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_roles_name UNIQUE (name)
);

COMMENT ON TABLE  roles IS 'Master role sistem (7 baris). Referensi tetap, tidak boleh dihapus selama masih dipakai (FK user_roles ON DELETE RESTRICT).';
COMMENT ON COLUMN roles.name IS 'Nilai kode role: admin, waka_kurikulum, waka_kesiswaan, guru_mapel, wali_kelas, siswa_inti, siswa';

-- -----------------------------------------------------------------------------
-- 2. users - akun seluruh pengguna (siswa & non-siswa)
--    Kolom & constraint mengikuti PRD EPIC 1 Bagian 8 + kebijakan Bagian 3
--    (is_active, failed_login_attempts, locked_until).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id                   bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                 varchar(150) NOT NULL,
    email                varchar(255) NOT NULL,
    username             varchar(50),
    password_hash        varchar(255),
    nisn                 varchar(10),
    google_id            varchar(255),
    avatar_url           varchar(500),
    is_active            boolean      NOT NULL DEFAULT true,
    failed_login_attempts smallint    NOT NULL DEFAULT 0,
    locked_until         timestamptz,
    password_changed_at  timestamptz,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),

    -- Kekuatan password dicek di aplikasi (bcrypt/argon2), di sini hanya
    -- memastikan format hash (bcrypt & argon2 keduanya diawali karakter "$").
    CONSTRAINT ck_users_password_hash
        CHECK (password_hash IS NULL OR password_hash LIKE '$%'),

    -- NISN: 10 digit angka, hanya diisi akun dengan role Siswa
    CONSTRAINT ck_users_nisn_format
        CHECK (nisn IS NULL OR nisn ~ '^[0-9]{10}$'),

    -- Lockout sementara (PRD Bagian 3.B): counter tidak boleh negatif
    CONSTRAINT ck_users_failed_login_attempts
        CHECK (failed_login_attempts >= 0),

    -- Akun tanpa password hanya sah bila memang terhubung ke Google
    CONSTRAINT ck_users_password_or_google
        CHECK (password_hash IS NOT NULL OR google_id IS NOT NULL),

    -- Email disimpan lowercase (ditegakkan juga oleh trigger fn_users_normalize)
    CONSTRAINT ck_users_email_lowercase
        CHECK (email = lower(email)),

    -- Unik - pada PostgreSQL UNIQUE tetap mengizinkan banyak NULL,
    -- sehingga username/google_id/nisn boleh kosong bagi akun yang tidak relevan
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_nisn     UNIQUE (nisn),
    CONSTRAINT uq_users_google   UNIQUE (google_id)
);

-- Email case-insensitive: login & kirim OTP selalu memakai lower(email)
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower ON users (lower(email));

CREATE INDEX IF NOT EXISTS ix_users_active ON users (is_active) WHERE is_active = false;
CREATE INDEX IF NOT EXISTS ix_users_locked ON users (locked_until)   WHERE locked_until IS NOT NULL;

COMMENT ON TABLE  users IS 'Akun seluruh pengguna. Satu baris = satu akun login; role disimpan terpisah di user_roles (multi-role / union, tanpa role aktif per sesi).';
COMMENT ON COLUMN users.email                IS 'Wajib, unik case-insensitive. Dipakai untuk login dan tujuan kirim OTP.';
COMMENT ON COLUMN users.username             IS 'Alternatif login (opsional). Case-SENSITIVE.';
COMMENT ON COLUMN users.password_hash        IS 'Hash bcrypt/argon2 - tidak pernah plaintext. NULL untuk akun yang hanya login via Google.';
COMMENT ON COLUMN users.nisn                 IS 'Hanya untuk akun siswa. Format 10 digit angka.';
COMMENT ON COLUMN users.google_id            IS 'sub akun Google; diisi lewat Google Sign-In / saat link akun (kasus 3 tabel Kebijakan Google Sign-In).';
COMMENT ON COLUMN users.is_active            IS 'true=aktif, false=dinonaktifkan Admin (Epic 2 / Next Semester). Hanya 2 status - tidak ada pending/locked permanen.';
COMMENT ON COLUMN users.failed_login_attempts IS 'Counter gagal login berturut-turut; di-reset ke 0 saat login berhasil (PRD 3.B).';
COMMENT ON COLUMN users.locked_until         IS 'Akun terkunci sementara sampai waktu ini (5 gagal / 15 menit -> kunci 15 menit).';
COMMENT ON COLUMN users.password_changed_at  IS 'Waktu terakhir password berubah - dipakai untuk audit & invalidasi sesi.';

-- -----------------------------------------------------------------------------
-- 3. user_roles - pivot multi-role (F1.8: akses = union seluruh role akun)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_roles (
    id         bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint      NOT NULL,
    role_id    smallint    NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_user_roles        UNIQUE (user_id, role_id),
    CONSTRAINT fk_user_roles_user   FOREIGN KEY (user_id)
        REFERENCES users (id)  ON DELETE CASCADE,
    CONSTRAINT fk_user_roles_role   FOREIGN KEY (role_id)
        REFERENCES roles (id)  ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS ix_user_roles_role ON user_roles (role_id);

COMMENT ON TABLE  user_roles IS 'Satu akun boleh >1 role (union, tanpa pilih/ganti role). UNIQUE(user_id,role_id) mencegah role ganda.';
COMMENT ON COLUMN user_roles.created_at IS 'Waktu role diberikan (oleh Admin, atau otomatis "siswa" saat registrasi).';

-- -----------------------------------------------------------------------------
-- 4. otp_codes - OTP untuk Ganti Password (F1.4) & Reset Password (F1.5)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otp_codes (
    id           bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint       NOT NULL,
    code_hash    varchar(255) NOT NULL,
    purpose      varchar(30)  NOT NULL,
    expired_at   timestamptz  NOT NULL,
    last_sent_at timestamptz  NOT NULL DEFAULT now(),
    is_used      boolean      NOT NULL DEFAULT false,
    attempt_count smallint    NOT NULL DEFAULT 0,
    created_at   timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT ck_otp_purpose CHECK (purpose IN ('change_password', 'reset_password')),
    CONSTRAINT ck_otp_expired CHECK (expired_at > created_at),
    CONSTRAINT ck_otp_attempts CHECK (attempt_count >= 0),
    CONSTRAINT fk_otp_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE
);

-- Cari OTP aktif terbaru milik user untuk suatu purpose (validasi + deteksi "satu aktif per user/purpose")
CREATE INDEX IF NOT EXISTS ix_otp_active
    ON otp_codes (user_id, purpose, created_at DESC)
    WHERE is_used = false;

COMMENT ON TABLE  otp_codes IS 'Kode OTP (hash, 8 karakter huruf besar+angka). Terisolasi per purpose: change_password tidak bisa dipakai di reset_password.';
COMMENT ON COLUMN otp_codes.code_hash    IS 'Hash OTP - teks asli TIDAK pernah disimpan.';
COMMENT ON COLUMN otp_codes.last_sent_at IS 'Waktu kirim terakhir - dasar cooldown resend 60 detik & batas 5 resend/jam (F1.6).';
COMMENT ON COLUMN otp_codes.attempt_count IS 'Percobaan verifikasi salah. Maksimal 5 -> kode batal meski benar (F1.6). Di-increment oleh aplikasi.';

-- -----------------------------------------------------------------------------
-- 5. sessions - 1 baris = 1 sesi login / 1 device (F1.7)
--    Tidak ada kolom "role aktif" - otorisasi selalu dari union user_roles.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessions (
    id                 bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id            bigint       NOT NULL,
    refresh_token_hash varchar(255) NOT NULL,
    device_info        varchar(255),
    ip_address         inet,
    user_agent         varchar(500),
    expired_at         timestamptz  NOT NULL,
    revoked_at         timestamptz,
    last_used_at       timestamptz,
    created_at         timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT ck_sessions_expired CHECK (expired_at > created_at),
    CONSTRAINT uq_sessions_refresh UNIQUE (refresh_token_hash),
    CONSTRAINT fk_sessions_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE
);

-- Pencarian sesi aktif milik satu user (refresh & cek validitas)
CREATE INDEX IF NOT EXISTS ix_sessions_user ON sessions (user_id, expired_at);
-- Invalidasi massal saat ganti/reset password: UPDATE ... WHERE user_id = ? AND revoked_at IS NULL
CREATE INDEX IF NOT EXISTS ix_sessions_user_live ON sessions (user_id) WHERE revoked_at IS NULL;

COMMENT ON TABLE  sessions IS 'Sesi login per device. Multi-device diperbolehkan; logout = revoke baris ini saja; ganti/reset password = revoke SELURUH baris user.';
COMMENT ON COLUMN sessions.refresh_token_hash IS 'Hash refresh token (access token 15 menit tidak disimpan di DB).';
COMMENT ON COLUMN sessions.revoked_at IS 'Soft-revoke: logout (baris ini saja) atau ganti/reset password (semua baris milik user).';
COMMENT ON COLUMN sessions.last_used_at IS 'Aktivitas terakhir - bermanfaat untuk deteksi sesi mencurigakan / cleanup.';

-- -----------------------------------------------------------------------------
-- 6. Seed 7 role (idempotent)
-- -----------------------------------------------------------------------------
INSERT INTO roles (name, description) VALUES
    ('admin',          'Admin / Staf Kurikulum - operator sistem, web/desktop only'),
    ('waka_kurikulum', 'Waka Kurikulum - kewenangan akademik, web/desktop only'),
    ('waka_kesiswaan', 'Waka Kesiswaan - pemantauan absensi siswa, web/desktop only'),
    ('guru_mapel',     'Guru Mata Pelajaran - pelaksana absensi & jurnal (web + mobile)'),
    ('wali_kelas',     'Wali Kelas - role tambahan pada akun Guru (web + mobile)'),
    ('siswa_inti',     'Siswa Inti / Pengurus Kelas (Ketua, Wakil, Sekretaris 1-2) - role tambahan pada akun Siswa (web + mobile)'),
    ('siswa',          'Siswa - satu-satunya role dengan registrasi mandiri (web + mobile)')
ON CONFLICT (name) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 7. Trigger: normalisasi input & auto-update updated_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_users_normalize () RETURNS trigger AS $$
BEGIN
    NEW.email := lower(btrim(NEW.email));
    IF NEW.username IS NOT NULL THEN
        NEW.username := btrim(NEW.username);
    END IF;
    IF NEW.nisn IS NOT NULL THEN
        NEW.nisn := btrim(NEW.nisn);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_set_updated_at () RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_normalize ON users;
CREATE TRIGGER trg_users_normalize
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_users_normalize();

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMIT;

-- =============================================================================
-- Verifikasi ringkas (jalankan manual setelah import):
--   \dt
--   SELECT r.name, count(ur.user_id) AS jumlah_pengguna
--   FROM roles r LEFT JOIN user_roles ur ON ur.role_id = r.id
--   GROUP BY r.name ORDER BY r.id;
-- =============================================================================
