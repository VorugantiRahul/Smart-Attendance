-- ==============================================================================
-- Sample Development Seed Data (Safe for Supabase Auth)
-- ==============================================================================

DO $$
DECLARE
  v_student_id UUID := '11111111-1111-1111-1111-111111111111';
  v_teacher_id UUID := '22222222-2222-2222-2222-222222222222';
  v_admin_id   UUID := '33333333-3333-3333-3333-333333333333';
  v_loc_id     UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_course_id  UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_session_id UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
BEGIN

  -- 1. Create matching users in Supabase auth.users table
  -- Password for all seed users is set to: Pass12345 (hashed with standard bcrypt)
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  VALUES
    (
      '00000000-0000-0000-0000-000000000000',
      v_student_id,
      'authenticated',
      'authenticated',
      'student@university.edu',
      crypt('Pass12345', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}',
      '{"full_name":"Alex Morgan","role":"student","student_id_number":"STU-2026-9481","department":"Computer Science & Engineering"}',
      now(),
      now()
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      v_teacher_id,
      'authenticated',
      'authenticated',
      'faculty@university.edu',
      crypt('Pass12345', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}',
      '{"full_name":"Prof. Evelyn Reed","role":"teacher","department":"Computer Science & Engineering"}',
      now(),
      now()
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      v_admin_id,
      'authenticated',
      'authenticated',
      'admin@university.edu',
      crypt('Pass12345', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}',
      '{"full_name":"Dr. Arthur Vance","role":"admin","department":"Campus Security & Administration"}',
      now(),
      now()
    )
  ON CONFLICT (id) DO NOTHING;

  -- 2. Upsert matching profiles in public.profiles table
  INSERT INTO public.profiles (id, email, full_name, role, student_id_number, department, is_iris_enrolled)
  VALUES
    (v_student_id, 'student@university.edu', 'Alex Morgan', 'student', 'STU-2026-9481', 'Computer Science & Engineering', TRUE),
    (v_teacher_id, 'faculty@university.edu', 'Prof. Evelyn Reed', 'teacher', NULL, 'Computer Science & Engineering', TRUE),
    (v_admin_id,   'admin@university.edu',   'Dr. Arthur Vance',  'admin',   NULL, 'Campus Security & Administration', FALSE)
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    role = EXCLUDED.role;

  -- 3. Campus Location & PostGIS Geofence Polygon (VNR VJIET Bachupally Campus: 17.5385° N, 78.3852° E, 350m buffer)
  INSERT INTO public.campus_locations (
    id,
    code,
    name,
    description,
    center_point,
    boundary_polygon,
    buffer_radius_meters,
    created_by
  )
  VALUES (
    v_loc_id,
    'VNRVJIET-MAIN',
    'VNR Vignana Jyothi Institute of Engineering & Technology',
    'Main Academic Complex (Accepted inside campus, >100m past main gate)',
    ST_SetSRID(ST_MakePoint(78.3852, 17.5385), 4326)::geography,
    ST_SetSRID(
      ST_MakePolygon(
        ST_GeomFromText(
          'LINESTRING(78.3820 17.5360, 78.3880 17.5360, 78.3880 17.5410, 78.3820 17.5410, 78.3820 17.5360)'
        )
      ),
      4326
    )::geography,
    350.0,
    v_admin_id
  )
  ON CONFLICT (id) DO UPDATE SET
    code = EXCLUDED.code,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    center_point = EXCLUDED.center_point,
    boundary_polygon = EXCLUDED.boundary_polygon,
    buffer_radius_meters = EXCLUDED.buffer_radius_meters;

  -- 4. Course Creation
  INSERT INTO public.courses (id, code, name, department)
  VALUES (
    v_course_id,
    'CS-402',
    'Distributed Systems & Edge Computing',
    'Computer Science & Engineering'
  )
  ON CONFLICT (code) DO NOTHING;

  -- 5. Instructor Assignment
  INSERT INTO public.course_instructors (course_id, instructor_id, academic_term)
  VALUES (v_course_id, v_teacher_id, '2026-FALL')
  ON CONFLICT ON CONSTRAINT unique_course_instructor DO NOTHING;

  -- 6. Student Enrollment
  INSERT INTO public.course_enrollments (course_id, student_id, academic_term)
  VALUES (v_course_id, v_student_id, '2026-FALL')
  ON CONFLICT ON CONSTRAINT unique_student_course_term DO NOTHING;

  -- 7. Active Attendance Session
  INSERT INTO public.attendance_sessions (
    id,
    course_id,
    instructor_id,
    location_id,
    session_title,
    status,
    start_time,
    end_time,
    verification_window_minutes
  )
  VALUES (
    v_session_id,
    v_course_id,
    v_teacher_id,
    v_loc_id,
    'Lecture 04: Biometric Edge Architectures',
    'active',
    now() - interval '5 minutes',
    now() + interval '25 minutes',
    30
  )
  ON CONFLICT (id) DO NOTHING;

  -- 8. Biometric Template Metadata (Zero raw image, cryptographic hash only)
  INSERT INTO public.biometric_templates (
    user_id,
    algorithm_version,
    template_hash,
    feature_vector_dimension,
    quality_metric,
    enrolled_device_id
  )
  VALUES (
    v_student_id,
    'v2.4-edge',
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    512,
    0.98,
    'DEV-EDGE-SCANNER-01'
  )
  ON CONFLICT (user_id) DO NOTHING;

  -- 9. Sample Audit Log
  INSERT INTO public.audit_logs (actor_id, action, resource_type, resource_id, details)
  VALUES (
    v_admin_id,
    'session_created',
    'attendance_sessions',
    v_session_id::text,
    '{"reason": "Initial semester seed data initialized"}'::jsonb
  );

END $$;
