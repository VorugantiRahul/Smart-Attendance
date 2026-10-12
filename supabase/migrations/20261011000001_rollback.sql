-- ==============================================================================
-- Rollback Migration for 20261011000001_initial_schema.sql
-- ==============================================================================

-- 1. Drop Functions & Triggers
DROP FUNCTION IF EXISTS public.submit_attendance_check_in(UUID, DOUBLE PRECISION, DOUBLE PRECISION, JSONB) CASCADE;
DROP FUNCTION IF EXISTS public.is_teacher(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.is_admin(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

-- 2. Drop Tables (in reverse dependency order)
DROP TABLE IF EXISTS public.audit_logs CASCADE;
DROP TABLE IF EXISTS public.biometric_templates CASCADE;
DROP TABLE IF EXISTS public.attendance_records CASCADE;
DROP TABLE IF EXISTS public.attendance_sessions CASCADE;
DROP TABLE IF EXISTS public.course_enrollments CASCADE;
DROP TABLE IF EXISTS public.course_instructors CASCADE;
DROP TABLE IF EXISTS public.courses CASCADE;
DROP TABLE IF EXISTS public.campus_locations CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- 3. Drop Custom Types
DROP TYPE IF EXISTS public.audit_action CASCADE;
DROP TYPE IF EXISTS public.attendance_status CASCADE;
DROP TYPE IF EXISTS public.session_status CASCADE;
DROP TYPE IF EXISTS public.app_role CASCADE;
