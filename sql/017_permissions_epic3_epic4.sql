-- =============================================================================
-- E-Absensi - 017: Permission Epic 3 dan Epic 4
-- PostgreSQL (target: PostgreSQL 12+; diuji pada PostgreSQL 18)
--
-- Jalankan:
--   psql -U akyrr -d absensi -v ON_ERROR_STOP=1 -f database\sql\017_permissions_epic3_epic4.sql
--
-- Isi perubahan:
--   1. 17 permission Epic 3 (student, teacher, class, subject, academic_year).
--   2. 6 permission Epic 4 (schedule).
--   3. Grant sesuai matriks hak akses PRD Epic 3 dan Epic 4.
--
-- Catatan:
--   - Role guru memakai kode guru_mapel.
--   - Grant bersifat idempotent: INSERT ... ON CONFLICT DO NOTHING.
--   - Permission hanya menambah; tidak menghapus grant Epic 2.
--
-- Idempotent: ON CONFLICT untuk permissions dan role_permissions.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO permissions (code, module, description) VALUES
    -- Epic 3
    ('student.view',           'student',       'Melihat daftar dan detail siswa'),
    ('student.update',         'student',       'Mengubah nama, NISN, dan kelas siswa'),
    ('teacher.view',           'teacher',       'Melihat daftar dan detail data guru'),
    ('teacher.create',         'teacher',       'Menambah data guru'),
    ('teacher.update',         'teacher',       'Mengubah data guru'),
    ('class.view',             'class',         'Melihat daftar dan detail kelas'),
    ('class.create',           'class',         'Menambah kelas'),
    ('class.update',           'class',         'Mengubah atau menonaktifkan kelas'),
    ('class.delete',           'class',         'Menghapus kelas'),
    ('subject.view',           'subject',       'Melihat daftar mata pelajaran'),
    ('subject.create',         'subject',       'Menambah mata pelajaran'),
    ('subject.update',         'subject',       'Mengubah atau menonaktifkan mata pelajaran'),
    ('subject.delete',         'subject',       'Menghapus mata pelajaran'),
    ('academic_year.view',     'academic_year', 'Melihat daftar tahun ajaran'),
    ('academic_year.create',   'academic_year', 'Menambah tahun ajaran'),
    ('academic_year.update',   'academic_year', 'Mengubah tahun ajaran'),
    ('academic_year.delete',   'academic_year', 'Menghapus tahun ajaran'),
    -- Epic 4
    ('schedule.download_template', 'schedule',  'Mengunduh template Excel jadwal'),
    ('schedule.import',            'schedule',  'Upload, validasi, dan konfirmasi import jadwal'),
    ('schedule.view',              'schedule',  'Melihat jadwal sesuai cakupan role'),
    ('schedule.update',            'schedule',  'Mengubah baris jadwal'),
    ('schedule.delete',            'schedule',  'Menghapus baris jadwal'),
    ('schedule.convert_activity',  'schedule',  'Mengubah jadwal menjadi kegiatan dan membatalkannya')
ON CONFLICT (code)
DO UPDATE SET module      = EXCLUDED.module,
              description = EXCLUDED.description;

-- Matriks grant Epic 3 dan Epic 4.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM (VALUES
        -- Epic 3: siswa
        ('student.view',              'admin'),
        ('student.view',              'waka_kurikulum'),
        ('student.view',              'waka_kesiswaan'),
        ('student.view',              'wali_kelas'),
        ('student.update',            'admin'),
        ('student.update',            'waka_kurikulum'),
        -- Epic 3: guru
        ('teacher.view',              'admin'),
        ('teacher.view',              'waka_kurikulum'),
        ('teacher.create',            'admin'),
        ('teacher.create',            'waka_kurikulum'),
        ('teacher.update',            'admin'),
        ('teacher.update',            'waka_kurikulum'),
        -- Epic 3: kelas
        ('class.view',                'admin'),
        ('class.view',                'waka_kurikulum'),
        ('class.view',                'waka_kesiswaan'),
        ('class.view',                'guru_mapel'),
        ('class.view',                'wali_kelas'),
        ('class.view',                'siswa_inti'),
        ('class.view',                'siswa'),
        ('class.create',              'admin'),
        ('class.create',              'waka_kurikulum'),
        ('class.update',              'admin'),
        ('class.update',              'waka_kurikulum'),
        ('class.delete',              'admin'),
        ('class.delete',              'waka_kurikulum'),
        -- Epic 3: mapel
        ('subject.view',              'admin'),
        ('subject.view',              'waka_kurikulum'),
        ('subject.view',              'guru_mapel'),
        ('subject.create',            'admin'),
        ('subject.create',            'waka_kurikulum'),
        ('subject.update',            'admin'),
        ('subject.update',            'waka_kurikulum'),
        ('subject.delete',            'admin'),
        ('subject.delete',            'waka_kurikulum'),
        -- Epic 3: tahun ajaran
        ('academic_year.view',        'admin'),
        ('academic_year.view',        'waka_kurikulum'),
        ('academic_year.create',      'admin'),
        ('academic_year.update',      'admin'),
        ('academic_year.update',      'waka_kurikulum'),
        ('academic_year.delete',      'admin'),
        -- Epic 4: jadwal
        ('schedule.download_template','admin'),
        ('schedule.import',           'admin'),
        ('schedule.view',             'admin'),
        ('schedule.view',             'waka_kurikulum'),
        ('schedule.view',             'waka_kesiswaan'),
        ('schedule.view',             'guru_mapel'),
        ('schedule.view',             'wali_kelas'),
        ('schedule.view',             'siswa_inti'),
        ('schedule.view',             'siswa'),
        ('schedule.update',           'admin'),
        ('schedule.update',           'waka_kurikulum'),
        ('schedule.delete',           'admin'),
        ('schedule.convert_activity', 'admin'),
        ('schedule.convert_activity', 'waka_kurikulum')
       ) AS g(code, role_name)
  JOIN roles r       ON r.name = g.role_name
  JOIN permissions p ON p.code = g.code
ON CONFLICT DO NOTHING;

COMMIT;

-- =============================================================================
-- Verifikasi ringkas:
--   SELECT count(*) FROM permissions;                  -- 30
--   SELECT module, count(*) FROM permissions GROUP BY module ORDER BY module;
--   SELECT r.name, count(*) FROM role_permissions rp
--     JOIN roles r ON r.id = rp.role_id GROUP BY r.name ORDER BY r.name;
-- =============================================================================
