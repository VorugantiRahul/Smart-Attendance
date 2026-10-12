-- Migration: Add Atithi Boys Hostel (Gandimaisamma) Location & Attendance Approval Enforcement
-- Description: Adds satellite faculty residence / duty location near Tryit Shop, Gandimaisamma
-- and reinforces admin approval requirement for faculty attendance check-ins.

INSERT INTO public.campus_locations (
    id,
    code,
    name,
    description,
    center_latitude,
    center_longitude,
    buffer_radius_meters,
    is_active,
    location_geog
) VALUES (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'ATITHI-HOSTEL-GM',
    'Atithi Boys Hostel (Near Tryit Shop, Gandimaisamma)',
    'Authorized Faculty Residence / Satellite Campus Zone near Tryit Shop, Gandimaisamma',
    17.578900,
    78.426900,
    250.0,
    true,
    ST_SetSRID(ST_MakePoint(78.426900, 17.578900), 4326)::geography
) ON CONFLICT (id) DO UPDATE SET
    center_latitude = EXCLUDED.center_latitude,
    center_longitude = EXCLUDED.center_longitude,
    buffer_radius_meters = EXCLUDED.buffer_radius_meters,
    location_geog = EXCLUDED.location_geog,
    is_active = true;

-- Update submit_attendance_check_in RPC to evaluate all active campus locations
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
    v_loc RECORD;
    v_is_within BOOLEAN := false;
    v_min_dist DOUBLE PRECISION := 999999.0;
    v_curr_dist DOUBLE PRECISION;
    v_user_point geography;
    v_today_start TIMESTAMPTZ := date_trunc('day', NOW());
    v_today_end TIMESTAMPTZ := v_today_start + interval '1 day';
    v_existing_id UUID;
    v_policy RECORD;
    v_is_late BOOLEAN := false;
    v_workday_start TIME;
    v_grace_cutoff TIME;
    v_now_time TIME := LOCALTIME;
    v_record_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated request';
    END IF;

    -- Verify profile authorization
    SELECT role, COALESCE(is_approved, false) INTO v_user_role, v_is_approved
    FROM public.profiles WHERE id = v_user_id;

    IF v_is_approved IS NOT TRUE THEN
        RAISE EXCEPTION 'Account pending administrator approval. Please contact the administrator to authorize your faculty account.';
    END IF;

    -- Prevent duplicate submissions on the same day
    SELECT id INTO v_existing_id
    FROM public.attendance_records
    WHERE student_id = v_user_id
      AND recorded_at >= v_today_start
      AND recorded_at < v_today_end
      AND status = 'present'
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        RAISE EXCEPTION 'Attendance already recorded for today. Duplicate submissions are strictly prevented.';
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
        IF v_now_time > v_grace_cutoff THEN
            v_is_late := true;
        END IF;
    END IF;

    -- Insert attendance record
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
        'is_late', v_is_late
    );
END;
$$;
