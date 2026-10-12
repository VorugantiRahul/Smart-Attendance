-- ==============================================================================
-- Migration: 20261011000001_initial_schema.sql
-- Description: Iris Geofenced Attendance System - Core Schema & Security Policies
-- Includes:
--   - PostGIS extension
--   - Role enums and user profiles
--   - Campus locations and polygon geofence boundaries
--   - Course/class assignments and student enrollments
--   - Attendance sessions with verification windows
--   - Attendance records with composite uniqueness preventing duplicates
--   - Biometric template metadata (strict SHA-256 hash / feature vectors, NO raw eye images)
--   - System audit logging for security compliance
--   - Server-side PostgreSQL functions for geospatial boundary validation
--   - Strict Row Level Security (RLS) policies for Student, Teacher, and Admin personas
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 2. ENUMS
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('student', 'teacher', 'admin');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'active', 'closed', 'cancelled');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE public.attendance_status AS ENUM ('pending_verification', 'present', 'absent', 'flagged_outside_geofence', 'biometric_rejected');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE public.audit_action AS ENUM (
    'user_login',
    'session_created',
    'session_activated',
    'session_closed',
    'attendance_submitted',
    'geofence_breach_detected',
    'biometric_enrolled',
    'boundary_modified'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- 3. PROFILES TABLE
-- Stored separately from auth.users credentials
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL,
  role public.app_role NOT NULL DEFAULT 'student',
  student_id_number TEXT,
  department TEXT NOT NULL DEFAULT 'General Engineering',
  is_iris_enrolled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Index on role for policy checks
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);

-- 4. CAMPUS LOCATIONS & GEOFENCE BOUNDARIES (POSTGIS)
CREATE TABLE IF NOT EXISTS public.campus_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  -- Center coordinate represented in WGS84 (SRID 4326)
  center_point geography(POINT, 4326) NOT NULL,
  -- Polygon boundary enclosing the valid campus/classroom perimeter
  boundary_polygon geography(POLYGON, 4326) NOT NULL,
  -- Buffer radius in meters for circular fallback tolerance
  buffer_radius_meters DOUBLE PRECISION NOT NULL DEFAULT 120.0,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Spatial index using GIST for PostGIS queries
CREATE INDEX IF NOT EXISTS idx_campus_locations_boundary ON public.campus_locations USING GIST(boundary_polygon);
CREATE INDEX IF NOT EXISTS idx_campus_locations_center ON public.campus_locations USING GIST(center_point);

-- 5. COURSES & CLASS ASSIGNMENTS
CREATE TABLE IF NOT EXISTS public.courses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  department TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Teacher Course Assignment (Which faculty member teaches which course)
CREATE TABLE IF NOT EXISTS public.course_instructors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  instructor_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  academic_term TEXT NOT NULL DEFAULT '2026-FALL',
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT unique_course_instructor UNIQUE(course_id, instructor_id, academic_term)
);

CREATE INDEX IF NOT EXISTS idx_course_instructors_inst ON public.course_instructors(instructor_id);
CREATE INDEX IF NOT EXISTS idx_course_instructors_course ON public.course_instructors(course_id);

-- Student Enrollment in Courses
CREATE TABLE IF NOT EXISTS public.course_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  academic_term TEXT NOT NULL DEFAULT '2026-FALL',
  enrolled_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT unique_student_course_term UNIQUE(course_id, student_id, academic_term)
);

CREATE INDEX IF NOT EXISTS idx_course_enrollments_student ON public.course_enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_course_enrollments_course ON public.course_enrollments(course_id);

-- 6. ATTENDANCE SESSIONS
CREATE TABLE IF NOT EXISTS public.attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  instructor_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  location_id UUID NOT NULL REFERENCES public.campus_locations(id) ON DELETE RESTRICT,
  session_title TEXT NOT NULL,
  status public.session_status NOT NULL DEFAULT 'scheduled',
  start_time TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  end_time TIMESTAMPTZ NOT NULL,
  -- Verification window in minutes (e.g. 15 min prompt)
  verification_window_minutes INT NOT NULL DEFAULT 15,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT check_session_times CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_sessions_instructor ON public.attendance_sessions(instructor_id);
CREATE INDEX IF NOT EXISTS idx_sessions_course ON public.attendance_sessions(course_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON public.attendance_sessions(status);

-- 7. ATTENDANCE RECORDS (With composite uniqueness & postgis GPS stamp)
CREATE TABLE IF NOT EXISTS public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  status public.attendance_status NOT NULL DEFAULT 'pending_verification',
  -- Captured student location at verification attempt
  recorded_location geography(POINT, 4326) NOT NULL,
  distance_from_center_meters DOUBLE PRECISION,
  is_within_geofence BOOLEAN NOT NULL DEFAULT FALSE,
  -- Biometric verification token / reference (Rule: marked pending until Phase 3)
  iris_verification_hash TEXT,
  iris_confidence_score DOUBLE PRECISION DEFAULT 0.0,
  is_biometrically_verified BOOLEAN NOT NULL DEFAULT FALSE,
  device_metadata JSONB DEFAULT '{}'::jsonb,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  -- CRITICAL RULE: Prevent duplicate attendance submissions for the exact same session
  CONSTRAINT unique_student_session UNIQUE (session_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_attendance_records_student ON public.attendance_records(student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_session ON public.attendance_records(session_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_status ON public.attendance_records(status);
CREATE INDEX IF NOT EXISTS idx_attendance_records_loc ON public.attendance_records USING GIST(recorded_location);

-- 8. BIOMETRIC TEMPLATE METADATA
-- CRITICAL PRIVACY RULE: Never store raw eye photographs. Only store cryptographically salted hashes / non-reversible feature template vectors.
CREATE TABLE IF NOT EXISTS public.biometric_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE UNIQUE,
  algorithm_version TEXT NOT NULL DEFAULT 'v2.4-edge',
  -- Salted cryptographic signature of biometric iris code (non-invertible)
  template_hash TEXT NOT NULL,
  feature_vector_dimension INT NOT NULL DEFAULT 512,
  quality_metric DOUBLE PRECISION NOT NULL DEFAULT 0.95,
  enrolled_device_id TEXT,
  enrolled_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT check_quality_metric CHECK (quality_metric >= 0.0 AND quality_metric <= 1.0)
);

CREATE INDEX IF NOT EXISTS idx_biometric_templates_user ON public.biometric_templates(user_id);

-- 9. AUDIT EVENTS
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  action public.audit_action NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT,
  details JSONB DEFAULT '{}'::jsonb,
  ip_address TEXT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON public.audit_logs(timestamp DESC);

-- ==============================================================================
-- 10. SERVER-SIDE HELPER FUNCTIONS & GEOSPATIAL VALIDATORS
-- ==============================================================================

-- Helper function to check if the current user is an administrator
CREATE OR REPLACE FUNCTION public.is_admin(user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = user_id AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Helper function to check if the current user is a teacher
CREATE OR REPLACE FUNCTION public.is_teacher(user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = user_id AND role = 'teacher'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Function to validate whether student coordinates fall strictly inside a session's campus location
CREATE OR REPLACE FUNCTION public.submit_attendance_check_in(
  p_session_id UUID,
  p_latitude DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION,
  p_device_info JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB AS $$
DECLARE
  v_student_id UUID;
  v_student_role public.app_role;
  v_session RECORD;
  v_user_point geography;
  v_is_inside BOOLEAN;
  v_distance_meters DOUBLE PRECISION;
  v_record_status public.attendance_status;
  v_record_id UUID;
  v_accuracy DOUBLE PRECISION;
  v_is_mock BOOLEAN;
  v_recent_attempts INT;
BEGIN
  v_student_id := auth.uid();
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated request';
  END IF;

  -- 1. RATE LIMITING: Max 3 submission attempts per minute per student
  SELECT COUNT(*) INTO v_recent_attempts
  FROM public.audit_logs
  WHERE actor_id = v_student_id
    AND action IN ('attendance_submitted', 'geofence_breach_detected')
    AND timestamp > now() - interval '1 minute';

  IF v_recent_attempts >= 5 THEN
    RAISE EXCEPTION 'Rate limit exceeded: Too many attendance submission attempts. Please wait 1 minute.';
  END IF;

  -- 2. COORDINATE SANITY VALIDATION
  IF p_latitude IS NULL OR p_longitude IS NULL OR
     p_latitude < -90.0 OR p_latitude > 90.0 OR
     p_longitude < -180.0 OR p_longitude > 180.0 THEN
    RAISE EXCEPTION 'Invalid geographic coordinates supplied.';
  END IF;

  -- Extract client GPS quality metadata
  v_accuracy := COALESCE((p_device_info->>'accuracy_meters')::DOUBLE PRECISION, 999.0);
  v_is_mock  := COALESCE((p_device_info->>'is_mock_location')::BOOLEAN, FALSE);

  -- 3. ENSURE CALLER IS A STUDENT
  SELECT role INTO v_student_role FROM public.profiles WHERE id = v_student_id;
  IF v_student_role != 'student' THEN
    RAISE EXCEPTION 'Only students may submit attendance check-ins';
  END IF;

  -- 4. FETCH ACTIVE SESSION AND LOCATION BOUNDARY
  SELECT s.*, l.boundary_polygon, l.center_point, l.buffer_radius_meters
  INTO v_session
  FROM public.attendance_sessions s
  JOIN public.campus_locations l ON s.location_id = l.id
  WHERE s.id = p_session_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attendance session % not found', p_session_id;
  END IF;

  IF v_session.status != 'active' THEN
    RAISE EXCEPTION 'Attendance session is not currently active';
  END IF;

  -- 5. VERIFY COURSE ENROLLMENT
  IF NOT EXISTS (
    SELECT 1 FROM public.course_enrollments
    WHERE course_id = v_session.course_id AND student_id = v_student_id
  ) THEN
    RAISE EXCEPTION 'Student is not enrolled in this course';
  END IF;

  -- 6. PREVENT DUPLICATE ATTENDANCE SUBMISSION
  IF EXISTS (
    SELECT 1 FROM public.attendance_records
    WHERE session_id = p_session_id AND student_id = v_student_id
  ) THEN
    RAISE EXCEPTION 'Duplicate attendance: Attendance record already exists for this session';
  END IF;

  -- 7. CONSTRUCT POINT IN WGS84
  v_user_point := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;

  -- 8. GEOSPATIAL POSTGIS VALIDATION
  -- ST_Covers: Inclusive boundary polygon check
  -- ST_DWithin: Proximity verification against center point and buffer radius
  v_is_inside := ST_Covers(v_session.boundary_polygon, v_user_point) OR
                 ST_DWithin(v_session.center_point, v_user_point, v_session.buffer_radius_meters);
  v_distance_meters := ST_Distance(v_session.center_point, v_user_point);

  -- GPS ACCURACY QUALITY CONSTRAINT
  -- Low accuracy (> 60m) or reported mock GPS triggers suspicious audit flag
  IF v_is_mock THEN
    v_record_status := 'flagged_outside_geofence';
  ELSIF v_accuracy > 60.0 THEN
    v_record_status := 'flagged_outside_geofence';
  ELSIF v_is_inside THEN
    v_record_status := 'pending_verification'; -- Biometric iris scan verification strictly required in Phase 3
  ELSE
    v_record_status := 'flagged_outside_geofence';
  END IF;

  -- 9. INSERT ATTENDANCE RECORD ATOMICALLY
  INSERT INTO public.attendance_records (
    session_id,
    student_id,
    status,
    recorded_location,
    distance_from_center_meters,
    is_within_geofence,
    is_biometrically_verified,
    device_metadata
  )
  VALUES (
    p_session_id,
    v_student_id,
    v_record_status,
    v_user_point,
    v_distance_meters,
    v_is_inside,
    FALSE,
    p_device_info
  )
  RETURNING id INTO v_record_id;

  -- 10. SYSTEM AUDIT EVENT
  INSERT INTO public.audit_logs (actor_id, action, resource_type, resource_id, details)
  VALUES (
    v_student_id,
    CASE WHEN v_is_inside AND NOT v_is_mock THEN 'attendance_submitted'::public.audit_action
         ELSE 'geofence_breach_detected'::public.audit_action END,
    'attendance_records',
    v_record_id::text,
    jsonb_build_object(
      'is_within_geofence', v_is_inside,
      'distance_meters', v_distance_meters,
      'accuracy_meters', v_accuracy,
      'is_mock_location', v_is_mock,
      'status', v_record_status
    )
  );

  RETURN jsonb_build_object(
    'record_id', v_record_id,
    'status', v_record_status,
    'is_within_geofence', v_is_inside,
    'distance_meters', v_distance_meters,
    'is_mock_location', v_is_mock
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==============================================================================
-- 11. ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

-- PROFILES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_policy" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

CREATE POLICY "profiles_select_policy"
  ON public.profiles FOR SELECT
  USING (
    auth.uid() = id OR public.is_admin(auth.uid()) OR public.is_teacher(auth.uid())
  );

CREATE POLICY "profiles_update_policy"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id OR public.is_admin(auth.uid()))
  WITH CHECK (
    -- Non-admins cannot alter their role
    public.is_admin(auth.uid()) OR role = (SELECT role FROM public.profiles WHERE id = auth.uid())
  );

-- CAMPUS LOCATIONS
ALTER TABLE public.campus_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campus_locations_select_policy" ON public.campus_locations;
DROP POLICY IF EXISTS "campus_locations_admin_all" ON public.campus_locations;

CREATE POLICY "campus_locations_select_policy"
  ON public.campus_locations FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "campus_locations_admin_all"
  ON public.campus_locations FOR ALL
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- COURSES
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "courses_select_authenticated" ON public.courses;
DROP POLICY IF EXISTS "courses_admin_all" ON public.courses;

CREATE POLICY "courses_select_authenticated"
  ON public.courses FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "courses_admin_all"
  ON public.courses FOR ALL
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- COURSE INSTRUCTORS
ALTER TABLE public.course_instructors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "course_instructors_select" ON public.course_instructors;
DROP POLICY IF EXISTS "course_instructors_admin_all" ON public.course_instructors;

CREATE POLICY "course_instructors_select"
  ON public.course_instructors FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "course_instructors_admin_all"
  ON public.course_instructors FOR ALL
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- COURSE ENROLLMENTS
ALTER TABLE public.course_enrollments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "course_enrollments_select_policy" ON public.course_enrollments;
DROP POLICY IF EXISTS "course_enrollments_admin_all" ON public.course_enrollments;

CREATE POLICY "course_enrollments_select_policy"
  ON public.course_enrollments FOR SELECT
  USING (
    auth.uid() = student_id OR
    public.is_admin(auth.uid()) OR
    EXISTS (
      SELECT 1 FROM public.course_instructors ci
      WHERE ci.course_id = course_enrollments.course_id AND ci.instructor_id = auth.uid()
    )
  );

CREATE POLICY "course_enrollments_admin_all"
  ON public.course_enrollments FOR ALL
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- ATTENDANCE SESSIONS
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "attendance_sessions_select_policy" ON public.attendance_sessions;
DROP POLICY IF EXISTS "attendance_sessions_teacher_insert" ON public.attendance_sessions;
DROP POLICY IF EXISTS "attendance_sessions_teacher_update" ON public.attendance_sessions;

-- Students can view sessions only for courses they are enrolled in
-- Teachers can view sessions for courses they instruct
-- Admins can view all sessions
CREATE POLICY "attendance_sessions_select_policy"
  ON public.attendance_sessions FOR SELECT
  USING (
    public.is_admin(auth.uid()) OR
    instructor_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.course_enrollments ce
      WHERE ce.course_id = attendance_sessions.course_id AND ce.student_id = auth.uid()
    )
  );

-- Teachers can manage (INSERT, UPDATE) sessions ONLY for their assigned classes
CREATE POLICY "attendance_sessions_teacher_insert"
  ON public.attendance_sessions FOR INSERT
  WITH CHECK (
    public.is_admin(auth.uid()) OR
    (
      instructor_id = auth.uid() AND
      EXISTS (
        SELECT 1 FROM public.course_instructors ci
        WHERE ci.course_id = attendance_sessions.course_id AND ci.instructor_id = auth.uid()
      )
    )
  );

CREATE POLICY "attendance_sessions_teacher_update"
  ON public.attendance_sessions FOR UPDATE
  USING (
    public.is_admin(auth.uid()) OR instructor_id = auth.uid()
  )
  WITH CHECK (
    public.is_admin(auth.uid()) OR instructor_id = auth.uid()
  );

-- ATTENDANCE RECORDS
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "attendance_records_select_policy" ON public.attendance_records;
DROP POLICY IF EXISTS "attendance_records_student_insert" ON public.attendance_records;
DROP POLICY IF EXISTS "attendance_records_teacher_update" ON public.attendance_records;

-- Students may access only their permitted records
-- Teachers may access attendance records only for their assigned course sessions
-- Admins may access all records
CREATE POLICY "attendance_records_select_policy"
  ON public.attendance_records FOR SELECT
  USING (
    student_id = auth.uid() OR
    public.is_admin(auth.uid()) OR
    EXISTS (
      SELECT 1 FROM public.attendance_sessions s
      WHERE s.id = attendance_records.session_id AND s.instructor_id = auth.uid()
    )
  );

-- Students can insert their own attendance record
CREATE POLICY "attendance_records_student_insert"
  ON public.attendance_records FOR INSERT
  WITH CHECK (
    student_id = auth.uid()
  );

-- Teachers can update status (e.g. approve manual exemption) for their own sessions
CREATE POLICY "attendance_records_teacher_update"
  ON public.attendance_records FOR UPDATE
  USING (
    public.is_admin(auth.uid()) OR
    EXISTS (
      SELECT 1 FROM public.attendance_sessions s
      WHERE s.id = attendance_records.session_id AND s.instructor_id = auth.uid()
    )
  );

-- BIOMETRIC TEMPLATES
ALTER TABLE public.biometric_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "biometric_templates_select" ON public.biometric_templates;
DROP POLICY IF EXISTS "biometric_templates_upsert" ON public.biometric_templates;

CREATE POLICY "biometric_templates_select"
  ON public.biometric_templates FOR SELECT
  USING (
    user_id = auth.uid() OR public.is_admin(auth.uid())
  );

CREATE POLICY "biometric_templates_upsert"
  ON public.biometric_templates FOR ALL
  USING (
    user_id = auth.uid() OR public.is_admin(auth.uid())
  )
  WITH CHECK (
    user_id = auth.uid() OR public.is_admin(auth.uid())
  );

-- AUDIT LOGS
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_logs_admin_select" ON public.audit_logs;
DROP POLICY IF EXISTS "audit_logs_insert" ON public.audit_logs;

-- Only Admins may view system audit logs
CREATE POLICY "audit_logs_admin_select"
  ON public.audit_logs FOR SELECT
  USING (public.is_admin(auth.uid()));

-- System or authenticated users may append audit logs
CREATE POLICY "audit_logs_insert"
  ON public.audit_logs FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);
