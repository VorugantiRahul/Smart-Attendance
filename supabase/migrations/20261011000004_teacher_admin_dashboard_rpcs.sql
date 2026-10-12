-- Migration: 20261011000004_teacher_admin_dashboard_rpcs.sql
-- Description: RPCs for Audited Attendance Corrections, Template Deletion, and Boundary Management

-- 1. Audited Attendance Correction RPC
CREATE OR REPLACE FUNCTION public.correct_attendance_record(
    p_record_id UUID,
    p_new_status TEXT,
    p_justification TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_operator_id UUID;
    v_operator_role app_role;
    v_operator_email TEXT;
    v_record RECORD;
    v_previous_status TEXT;
BEGIN
    v_operator_id := auth.uid();
    IF v_operator_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated request';
    END IF;

    -- Validate operator permissions (Teacher or Admin only)
    SELECT role, email INTO v_operator_role, v_operator_email
    FROM public.profiles
    WHERE id = v_operator_id;

    IF v_operator_role NOT IN ('teacher', 'admin') THEN
        RAISE EXCEPTION 'Unauthorized: Only teachers and administrators can perform attendance corrections';
    END IF;

    IF TRIM(p_justification) = '' OR p_justification IS NULL THEN
        RAISE EXCEPTION 'Audit Compliance: Justification reason is strictly required for attendance corrections';
    END IF;

    SELECT * INTO v_record FROM public.attendance_records WHERE id = p_record_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attendance record not found: %', p_record_id;
    END IF;

    v_previous_status := v_record.status;

    -- Update attendance record with correction metadata
    UPDATE public.attendance_records
    SET status = p_new_status::attendance_status,
        correction_reason = p_justification,
        corrected_by = v_operator_email
    WHERE id = p_record_id;

    -- Insert Audit Event
    INSERT INTO public.audit_logs (user_id, actor_email, action, table_name, record_id, details)
    VALUES (
        v_operator_id,
        v_operator_email,
        'ATTENDANCE_MANUAL_CORRECTION',
        'attendance_records',
        p_record_id,
        jsonb_build_object(
            'previous_status', v_previous_status,
            'new_status', p_new_status,
            'justification', p_justification,
            'student_id', v_record.student_id,
            'session_id', v_record.session_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'record_id', p_record_id,
        'previous_status', v_previous_status,
        'new_status', p_new_status
    );
END;
$$;

-- 2. Biometric Template Deletion RPC (Right to be forgotten)
CREATE OR REPLACE FUNCTION public.delete_biometric_template(
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role app_role;
    v_caller_email TEXT;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated request';
    END IF;

    SELECT role, email INTO v_caller_role, v_caller_email
    FROM public.profiles
    WHERE id = v_caller_id;

    IF v_caller_role != 'admin' AND v_caller_id != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: Users can only purge their own biometric template or require Admin permissions';
    END IF;

    -- Delete template
    DELETE FROM public.biometric_templates WHERE user_id = p_user_id;

    -- Update profile enrollment status
    UPDATE public.profiles
    SET is_iris_enrolled = FALSE
    WHERE id = p_user_id;

    -- Audit log biometric purging
    INSERT INTO public.audit_logs (user_id, actor_email, action, table_name, record_id, details)
    VALUES (
        v_caller_id,
        v_caller_email,
        'BIOMETRIC_TEMPLATE_PURGED',
        'biometric_templates',
        p_user_id,
        jsonb_build_object(
            'target_user_id', p_user_id,
            'compliance_policy', 'GDPR Art. 17 / DPDP Right to be Forgotten',
            'action_status', 'SECURELY_ERASED'
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'purged_user_id', p_user_id
    );
END;
$$;
