-- =============================================================================
-- E-Absensi - 024: Permission Epic 5 dan Epic 6
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\024_permissions_epic5_epic6.sql
--
-- Isi perubahan:
--   1. 8 permission Epic 5 (attendance, leave_request, permission_letter).
--   2. 5 permission Epic 6 (teacher_attendance).
--   3. 33 grant sesuai matriks PRD Epic 5 dan Epic 6.
--   4. Komentar target activity_logs ditambah tipe Epic 5/6.
--
-- Catatan:
--   - Grant idempotent: ON CONFLICT DO NOTHING, tidak menghapus grant lama.
--   - Total setelah migrasi: 43 permission, 94 role_permissions (DB bersih).
--   - Cakupan data (kelas sendiri, guru sendiri) tetap divalidasi Backend;
--     permission hanya menentukan akses fitur.
--
-- Idempotent: ON CONFLICT untuk permissions dan role_permissions.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO permissions (code, module, description) VALUES
    -- Epic 5
    ('attendance.input',              'attendance',        'Mengisi ceklis absensi siswa'),
    ('attendance.input_fallback',     'attendance',        'Mengisi absensi fallback Wali Kelas'),
    ('attendance.update',             'attendance',        'Mengubah absensi yang sudah tercatat'),
    ('attendance.view',               'attendance',        'Melihat dan memfilter absensi siswa'),
    ('attendance.export',             'attendance',        'Melihat rekap dan mengekspor absensi'),
    ('leave_request.submit',          'leave_request',     'Mengajukan Form Izin/Sakit'),
    ('leave_request.review',          'leave_request',     'Menyetujui atau menolak pengajuan izin'),
    ('permission_letter.upload',      'permission_letter', 'Mengunggah surat pulang/dispensasi'),
    -- Epic 6
    ('teacher_attendance.generate_qr','teacher_attendance','Generate QR dan kode cadangan kehadiran guru'),
    ('teacher_attendance.confirm',    'teacher_attendance','Scan QR atau input kode cadangan'),
    ('teacher_attendance.view',       'teacher_attendance','Melihat dan memfilter kehadiran guru'),
    ('teacher_attendance.annotate',   'teacher_attendance','Menganotasi dan mengoreksi kehadiran guru'),
    ('teacher_attendance.export',     'teacher_attendance','Merekap dan mengekspor kehadiran guru')
ON CONFLICT (code)
DO UPDATE SET module      = EXCLUDED.module,
              description = EXCLUDED.description;

-- Matriks grant Epic 5 dan Epic 6.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM (VALUES
        -- Epic 5: absensi siswa
        ('attendance.input',               'guru_mapel'),
        ('attendance.input_fallback',      'wali_kelas'),
        ('attendance.update',              'admin'),
        ('attendance.update',              'waka_kurikulum'),
        ('attendance.update',              'guru_mapel'),
        ('attendance.update',              'wali_kelas'),
        ('attendance.view',                'admin'),
        ('attendance.view',                'waka_kurikulum'),
        ('attendance.view',                'waka_kesiswaan'),
        ('attendance.view',                'guru_mapel'),
        ('attendance.view',                'wali_kelas'),
        ('attendance.view',                'siswa_inti'),
        ('attendance.view',                'siswa'),
        ('attendance.export',              'admin'),
        ('attendance.export',              'waka_kurikulum'),
        ('attendance.export',              'waka_kesiswaan'),
        ('attendance.export',              'guru_mapel'),
        ('attendance.export',              'wali_kelas'),
        -- Epic 5: izin/sakit
        ('leave_request.submit',           'siswa'),
        ('leave_request.submit',           'siswa_inti'),
        ('leave_request.review',           'wali_kelas'),
        -- Epic 5: surat
        ('permission_letter.upload',       'siswa_inti'),
        -- Epic 6: kehadiran guru
        ('teacher_attendance.generate_qr', 'siswa_inti'),
        ('teacher_attendance.generate_qr', 'wali_kelas'),
        ('teacher_attendance.confirm',     'guru_mapel'),
        ('teacher_attendance.view',        'admin'),
        ('teacher_attendance.view',        'waka_kurikulum'),
        ('teacher_attendance.view',        'guru_mapel'),
        ('teacher_attendance.annotate',    'admin'),
        ('teacher_attendance.annotate',    'waka_kurikulum'),
        ('teacher_attendance.export',      'admin'),
        ('teacher_attendance.export',      'waka_kurikulum'),
        ('teacher_attendance.export',      'guru_mapel')
       ) AS g(code, role_name)
  JOIN roles r       ON r.name = g.role_name
  JOIN permissions p ON p.code = g.code
ON CONFLICT DO NOTHING;

COMMENT ON COLUMN activity_logs.target_type IS
    'Tipe target generik: USER, STUDENT, TEACHER, CLASS, SUBJECT, ACADEMIC_YEAR, SCHEDULE, TEACHER_ATTENDANCE, STUDENT_ATTENDANCE, LEAVE_REQUEST, PERMISSION_LETTER, ALPHA_WARNING. Tanpa CHECK agar mudah bertambah.';

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM permissions;                          -- 43
--   SELECT module, count(*) FROM permissions GROUP BY module ORDER BY module;
--   SELECT count(*) FROM role_permissions;                     -- 94
--   SELECT r.name, count(*) FROM role_permissions rp
--     JOIN roles r ON r.id = rp.role_id GROUP BY r.name ORDER BY r.name;
-- =============================================================================
