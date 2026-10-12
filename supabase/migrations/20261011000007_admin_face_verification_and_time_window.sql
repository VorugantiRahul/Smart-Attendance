-- Migration: Admin Face Verification Approval, Time Window, and Duplicate Constraints
-- Schema updates supporting complete faculty face recognition attendance system

-- 1. Ensure profiles table has approval, status, and contact fields
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS phone TEXT,
    ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
    ADD COLUMN IF NOT EXISTS account_status TEXT DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'inactive')),
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES public.profiles(id);

-- 2. Prevent duplicate entries per faculty per day at the database constraint level
-- This enforces exactly one attendance entry per calendar day (Asia/Kolkata timezone)
CREATE UNIQUE INDEX IF NOT EXISTS uq_faculty_attendance_per_day
    ON public.attendance_records (student_id, ((recorded_at AT TIME ZONE 'Asia/Kolkata')::date));

-- 3. Dedicated Face Verifications table for audit and template tracking
CREATE TABLE IF NOT EXISTS public.faculty_face_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    photo_url TEXT,
    face_template_hash TEXT,
    approval_status TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
    reviewed_by UUID REFERENCES public.profiles(id),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS policies for faculty_face_verifications
ALTER TABLE public.faculty_face_verifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Faculty can view own face verification requests"
    ON public.faculty_face_verifications
    FOR SELECT
    TO authenticated
    USING (faculty_id = auth.uid());

CREATE POLICY "Faculty can insert own face verification request"
    ON public.faculty_face_verifications
    FOR INSERT
    TO authenticated
    WITH CHECK (faculty_id = auth.uid());

CREATE POLICY "Admins have full access to faculty face verifications"
    ON public.faculty_face_verifications
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- 4. Update submit_attendance_check_in RPC with strict 9:00 AM - 5:00 PM Asia/Kolkata enforcement and account status check
CREATE OR REPLACE FUNCTION public.submit_attendance_check_in(
    p_session_id UUID,
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_device_info JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_role TEXT;
    v_is_approved BOOLEAN;
    v_approval_status TEXT;
    v_account_status TEXT;
    v_loc RECORD;
    v_is_within BOOLEAN := false;
    v_min_dist DOUBLE PRECISION := 999999.0;
    v_curr_dist DOUBLE PRECISION;
    v_user_point geography;
    v_kolkata_now TIMESTAMPTZ := NOW() AT TIME ZONE 'Asia/Kolkata';
    v_kolkata_time TIME := (v_kolkata_now)::time;
    v_today_date DATE := (v_kolkata_now)::date;
    v_existing_id UUID;
    v_policy RECORD;
    v_is_late BOOLEAN := false;
    v_workday_start TIME := '09:00:00'::time;
    v_workday_end TIME := '17:00:00'::time;
    v_grace_cutoff TIME := '09:15:00'::time;
    v_record_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated request';
    END IF;

    -- Verify profile authorization and account status
    SELECT role, COALESCE(is_approved, false), COALESCE(approval_status, 'pending'), COALESCE(account_status, 'active')
    INTO v_user_role, v_is_approved, v_approval_status, v_account_status
    FROM public.profiles WHERE id = v_user_id;

    IF v_account_status = 'suspended' THEN
        RAISE EXCEPTION 'Faculty account has been suspended by an administrator.';
    END IF;

    IF v_account_status = 'inactive' THEN
        RAISE EXCEPTION 'Faculty account is deactivated.';
    END IF;

    IF v_is_approved IS NOT TRUE OR v_approval_status != 'approved' THEN
        RAISE EXCEPTION 'Account pending administrator approval. Please contact the administrator to authorize your faculty account.';
    END IF;

    -- Strict Attendance Window Enforcement (09:00:00 to 17:00:00 Asia/Kolkata)
    IF v_kolkata_time < v_workday_start THEN
        RAISE EXCEPTION 'Attendance is not open yet. You can mark attendance from 9:00 AM.';
    END IF;

    IF v_kolkata_time > v_workday_end THEN
        RAISE EXCEPTION 'The attendance window has closed for today.';
    END IF;

    -- Prevent duplicate submissions on the same date (Asia/Kolkata)
    SELECT id INTO v_existing_id
    FROM public.attendance_records
    WHERE student_id = v_user_id
      AND (recorded_at AT TIME ZONE 'Asia/Kolkata')::date = v_today_date
      AND status = 'present'
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        RAISE EXCEPTION 'Attendance already marked for today.';
    END IF;

    -- User GPS location point
    v_user_point := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;

    -- Evaluate against all active campus and satellite locations (VNR Campus & Gandimaisamma Hostel)
    FOR v_loc IN SELECT * FROM public.campus_locations WHERE is_active = true LOOP
        v_curr_dist := ST_Distance(v_user_point, v_loc.location_geog);
        IF v_curr_dist < v_min_dist THEN
            v_min_dist := v_curr_dist;
        END IF;
        IF v_curr_dist <= v_loc.buffer_radius_meters THEN
            v_is_within := true;
            v_min_dist := v_curr_dist;
            EXIT;
        END IF;
    END LOOP;

    -- Policy late check
    SELECT * INTO v_policy FROM public.attendance_policies LIMIT 1;
    IF v_policy IS NOT NULL THEN
        v_workday_start := make_time(v_policy.workday_start_hour, v_policy.workday_start_minute, 0.0);
        v_grace_cutoff := v_workday_start + (v_policy.grace_period_minutes || ' minutes')::interval;
    END IF;

    IF v_kolkata_time > v_grace_cutoff THEN
        v_is_late := true;
    END IF;

    -- Insert attendance record with exact server timestamp
    INSERT INTO public.attendance_records (
        session_id,
        student_id,
        status,
        latitude,
        longitude,
        distance_from_center_meters,
        is_within_geofence,
        is_late,
        is_biometrically_verified,
        device_metadata,
        recorded_at
    ) VALUES (
        p_session_id,
        v_user_id,
        CASE WHEN v_is_within THEN 'present'::attendance_status ELSE 'flagged_outside_geofence'::attendance_status END,
        p_latitude,
        p_longitude,
        v_min_dist,
        v_is_within,
        v_is_late,
        v_is_within,
        p_device_info,
        NOW()
    )
    RETURNING id INTO v_record_id;

    RETURN jsonb_build_object(
        'record_id', v_record_id,
        'is_within_geofence', v_is_within,
        'distance_meters', v_min_dist,
        'is_late', v_is_late,
        'recorded_at', NOW()
    );
END;
$$;
