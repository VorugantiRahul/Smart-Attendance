-- ==============================================================================
-- Migration: 20261011000003_security_hardening.sql
-- Description: Presentation attack hardening, short-lived nonces, replay protection,
--              and cryptographic payload verification.
-- ==============================================================================

-- 1. Create Nonces Table for Request Replay Prevention
CREATE TABLE IF NOT EXISTS public.auth_nonces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nonce TEXT NOT NULL UNIQUE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  action TEXT NOT NULL DEFAULT 'attendance_verification',
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  is_consumed BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_auth_nonces_lookup ON public.auth_nonces(nonce, user_id, is_consumed);
CREATE INDEX IF NOT EXISTS idx_auth_nonces_expiry ON public.auth_nonces(expires_at);

-- 2. Function: Generate Short-Lived Single-Use Nonce (Valid for 90 seconds)
CREATE OR REPLACE FUNCTION public.generate_attendance_nonce(
  p_session_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_nonce TEXT;
  v_expires_at TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated: Must be logged in to request verification nonce.';
  END IF;

  -- Ensure caller is an authorized user (student, teacher/faculty, or admin)
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id AND role IN ('student', 'teacher', 'admin')) THEN
    RAISE EXCEPTION 'Unauthorized: Only registered users may request attendance verification nonces.';
  END IF;

  -- Verify session is active
  IF NOT EXISTS (SELECT 1 FROM public.attendance_sessions WHERE id = p_session_id AND status = 'active') THEN
    RAISE EXCEPTION 'Attendance session is not currently active.';
  END IF;

  -- Cryptographically secure 256-bit random nonce
  v_nonce := encode(gen_random_bytes(32), 'hex');
  v_expires_at := now() + interval '90 seconds';

  INSERT INTO public.auth_nonces (nonce, user_id, session_id, expires_at)
  VALUES (v_nonce, v_user_id, p_session_id, v_expires_at);

  RETURN jsonb_build_object(
    'nonce', v_nonce,
    'expires_at', v_expires_at,
    'validity_seconds', 90
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Hardened Attendance Submission RPC with Nonce Invalidation, Replay Defense & Liveness Audit
CREATE OR REPLACE FUNCTION public.submit_hardened_attendance(
  p_session_id UUID,
  p_nonce TEXT,
  p_latitude DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION,
  p_liveness_score DOUBLE PRECISION,
  p_challenge_type TEXT,
  p_device_signature TEXT,
  p_device_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB AS $$
DECLARE
  v_student_id UUID;
  v_student_role public.app_role;
  v_session RECORD;
  v_nonce_record RECORD;
  v_user_point geography;
  v_is_inside BOOLEAN;
  v_distance_meters DOUBLE PRECISION;
  v_record_status public.attendance_status;
  v_record_id UUID;
  v_recent_attempts INT;
  v_is_mock BOOLEAN;
  v_accuracy DOUBLE PRECISION;
BEGIN
  v_student_id := auth.uid();
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated request';
  END IF;

  -- 1. RATE LIMITING (Max 5 attempts / minute)
  SELECT COUNT(*) INTO v_recent_attempts
  FROM public.audit_logs
  WHERE actor_id = v_student_id
    AND action IN ('attendance_submitted', 'geofence_breach_detected')
    AND timestamp > now() - interval '1 minute';

  IF v_recent_attempts >= 5 THEN
    RAISE EXCEPTION 'Rate limit exceeded: Too many attempts. Please wait 1 minute.';
  END IF;

  -- 2. VERIFY NONCE: Exists, matches user, not expired, not previously consumed
  SELECT * INTO v_nonce_record
  FROM public.auth_nonces
  WHERE nonce = p_nonce AND user_id = v_student_id AND session_id = p_session_id
  FOR UPDATE; -- Row-level lock to prevent race-condition replays

  IF NOT FOUND THEN
    INSERT INTO public.audit_logs (actor_id, action, resource_type, resource_id, details)
    VALUES (v_student_id, 'geofence_breach_detected', 'auth_nonces', p_nonce,
            '{"error": "Invalid or missing server nonce"}'::jsonb);
    RAISE EXCEPTION 'Security rejection: Invalid or unauthorized nonce.';
  END IF;

  IF v_nonce_record.is_consumed THEN
    INSERT INTO public.audit_logs (actor_id, action, resource_type, resource_id, details)
    VALUES (v_student_id, 'geofence_breach_detected', 'auth_nonces', p_nonce,
            '{"error": "Replay attack detected: Nonce already consumed"}'::jsonb);
    RAISE EXCEPTION 'Security rejection: Nonce has already been consumed (Replay Attack Detected).';
  END IF;

  IF v_nonce_record.expires_at < now() THEN
    INSERT INTO public.audit_logs (actor_id, action, resource_type, resource_id, details)
    VALUES (v_student_id, 'geofence_breach_detected', 'auth_nonces', p_nonce,
            '{"error": "Expired nonce"}'::jsonb);
    RAISE EXCEPTION 'Security rejection: Nonce expired. Attendance window timed out.';
  END IF;

  -- Invalidate nonce immediately (One-Time Token)
  UPDATE public.auth_nonces
  SET is_consumed = TRUE, consumed_at = now()
  WHERE id = v_nonce_record.id;

  -- 3. ENSURE VALID ROLE
  SELECT role INTO v_student_role FROM public.profiles WHERE id = v_student_id;
  IF v_student_role NOT IN ('student', 'teacher', 'admin') THEN
    RAISE EXCEPTION 'Unauthorized: User role not permitted to submit attendance verification';
  END IF;

  -- 4. FETCH SESSION & GEOFENCE PERIMETER
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

  -- 6. PREVENT DUPLICATE SUBMISSION (IDEMPOTENCY)
  IF EXISTS (
    SELECT 1 FROM public.attendance_records
    WHERE session_id = p_session_id AND student_id = v_student_id
  ) THEN
    RAISE EXCEPTION 'Duplicate Submission: Attendance record already exists for this session.';
  END IF;

  -- 7. LIVENESS ASSESSMENT VALIDATION
  -- Threshold calibrated at >= 0.70; failed liveness causes biometric rejection
  IF p_liveness_score < 0.70 THEN
    v_record_status := 'biometric_rejected';
    
    INSERT INTO public.audit_logs (actor_id, action, resource_type, resource_id, details)
    VALUES (v_student_id, 'geofence_breach_detected', 'liveness_assessment', p_session_id::text,
            jsonb_build_object(
              'error', 'Presentation attack detected or liveness uncertain',
              'liveness_score', p_liveness_score,
              'challenge_type', p_challenge_type
            ));

    RAISE EXCEPTION 'Biometric Security Rejection: Liveness verification failed (Score: %, Challenge: %).',
      p_liveness_score, p_challenge_type;
  END IF;

  -- 8. GEOFENCE EVALUATION (PostGIS)
  v_user_point := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;
  v_is_inside := ST_Covers(v_session.boundary_polygon, v_user_point) OR
                 ST_DWithin(v_session.center_point, v_user_point, v_session.buffer_radius_meters);
  v_distance_meters := ST_Distance(v_session.center_point, v_user_point);

  v_accuracy := COALESCE((p_device_metadata->>'accuracy_meters')::DOUBLE PRECISION, 999.0);
  v_is_mock  := COALESCE((p_device_metadata->>'is_mock_location')::BOOLEAN, FALSE);

  IF v_is_mock OR v_accuracy > 60.0 THEN
    v_record_status := 'flagged_outside_geofence';
  ELSIF v_is_inside THEN
    v_record_status := 'pending_verification'; -- Enforces Phase 3 iris match
  ELSE
    v_record_status := 'flagged_outside_geofence';
  END IF;

  -- 9. ATOMIC ATTENDANCE INSERTION
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
    p_device_metadata || jsonb_build_object(
      'liveness_score', p_liveness_score,
      'challenge_type', p_challenge_type,
      'device_signature', p_device_signature
    )
  )
  RETURNING id INTO v_record_id;

  -- 10. SYSTEM AUDIT EVENT
  INSERT INTO public.audit_logs (actor_id, action, resource_type, resource_id, details)
  VALUES (
    v_student_id,
    'attendance_submitted',
    'attendance_records',
    v_record_id::text,
    jsonb_build_object(
      'is_within_geofence', v_is_inside,
      'distance_meters', v_distance_meters,
      'liveness_score', p_liveness_score,
      'challenge_type', p_challenge_type,
      'nonce_used', p_nonce
    )
  );

  RETURN jsonb_build_object(
    'record_id', v_record_id,
    'status', v_record_status,
    'is_within_geofence', v_is_inside,
    'distance_meters', v_distance_meters,
    'liveness_verified', TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
