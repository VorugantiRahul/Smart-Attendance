-- ==============================================================================
-- 20261012000008_faculty_enrollment_workflow_and_verification.sql
-- Migration: Complete Faculty Biometric Enrollment Approval Workflow, Security Guards,
-- and Server-Enforced RPCs for Admin Authorization & Audit Logging.
-- ==============================================================================

-- 1. Ensure columns on profiles table
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES public.profiles(id),
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
    ADD COLUMN IF NOT EXISTS account_status TEXT DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'inactive')),
    ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT FALSE;

-- 2. Ensure faculty_face_verifications table exists with all required fields
CREATE TABLE IF NOT EXISTS public.faculty_face_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    photo_url TEXT,
    face_template_hash TEXT,
    iris_template_hash TEXT,
    approval_status TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
    reviewed_by UUID REFERENCES public.profiles(id),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure iris_template_hash and submitted_at exist if table was already created
ALTER TABLE public.faculty_face_verifications
    ADD COLUMN IF NOT EXISTS iris_template_hash TEXT,
    ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- 3. Unique index preventing duplicate pending enrollment requests per faculty
CREATE UNIQUE INDEX IF NOT EXISTS uq_faculty_pending_enrollment
    ON public.faculty_face_verifications (faculty_id)
    WHERE (approval_status = 'pending');

-- 4. Enable RLS on faculty_face_verifications
ALTER TABLE public.faculty_face_verifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Faculty can view own face verification requests" ON public.faculty_face_verifications;
CREATE POLICY "Faculty can view own face verification requests"
    ON public.faculty_face_verifications
    FOR SELECT
    TO authenticated
    USING (faculty_id = auth.uid());

DROP POLICY IF EXISTS "Admins have full access to faculty face verifications" ON public.faculty_face_verifications;
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

-- 5. RPC: Submit or Resubmit Faculty Enrollment Request
CREATE OR REPLACE FUNCTION public.submit_faculty_enrollment_request(
    p_photo_url TEXT,
    p_face_template_hash TEXT,
    p_iris_template_hash TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_role TEXT;
    v_email TEXT;
    v_req_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated request';
    END IF;

    SELECT role::text, email INTO v_role, v_email
    FROM public.profiles
    WHERE id = v_user_id;

    IF v_role NOT IN ('teacher', 'admin') THEN
        RAISE EXCEPTION 'Unauthorized: Only faculty members can submit biometric enrollment requests.';
    END IF;

    IF p_photo_url IS NULL OR TRIM(p_photo_url) = '' THEN
        RAISE EXCEPTION 'Validation failure: A valid facial photograph is required for enrollment.';
    END IF;

    -- Remove any previous pending request so new request is active (prevents duplicate pending)
    DELETE FROM public.faculty_face_verifications
    WHERE faculty_id = v_user_id AND approval_status = 'pending';

    -- Insert new enrollment request
    INSERT INTO public.faculty_face_verifications (
        faculty_id,
        photo_url,
        face_template_hash,
        iris_template_hash,
        approval_status,
        submitted_at,
        created_at
    ) VALUES (
        v_user_id,
        p_photo_url,
        p_face_template_hash,
        p_iris_template_hash,
        'pending',
        NOW(),
        NOW()
    )
    RETURNING id INTO v_req_id;

    -- Update profile status: attendance remains disabled until approved
    UPDATE public.profiles
    SET is_approved = FALSE,
        approval_status = 'pending',
        is_iris_enrolled = TRUE,
        avatar_url = p_photo_url,
        submitted_at = NOW(),
        rejection_reason = NULL,
        updated_at = NOW()
    WHERE id = v_user_id;

    -- Audit log
    INSERT INTO public.audit_logs (user_id, actor_email, action, table_name, record_id, details)
    VALUES (
        v_user_id,
        v_email,
        'FACULTY_ENROLLMENT_SUBMITTED',
        'faculty_face_verifications',
        v_req_id,
        jsonb_build_object(
            'faculty_id', v_user_id,
            'request_id', v_req_id,
            'has_iris_template', (p_iris_template_hash IS NOT NULL)
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'request_id', v_req_id,
        'status', 'pending'
    );
END;
$$;

-- 6. RPC: Server-Enforced Admin Approval of Faculty Enrollment
CREATE OR REPLACE FUNCTION public.approve_faculty_enrollment(
    p_faculty_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_admin_role TEXT;
    v_admin_email TEXT;
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated request';
    END IF;

    -- Verify caller is an authorized administrator
    SELECT role::text, email INTO v_admin_role, v_admin_email
    FROM public.profiles
    WHERE id = v_admin_id;

    IF v_admin_role != 'admin' THEN
        RAISE EXCEPTION 'Unauthorized: Only institutional administrators can approve faculty enrollment requests.';
    END IF;

    -- Security Guard: Faculty members must NEVER approve their own enrollment
    IF v_admin_id = p_faculty_id THEN
        RAISE EXCEPTION 'Security rejection: Administrators cannot approve their own biometric enrollment.';
    END IF;

    -- Update verification record
    UPDATE public.faculty_face_verifications
    SET approval_status = 'approved',
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        rejection_reason = NULL
    WHERE faculty_id = p_faculty_id;

    -- Update profiles record
    UPDATE public.profiles
    SET is_approved = TRUE,
        approval_status = 'approved',
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        rejection_reason = NULL,
        updated_at = NOW()
    WHERE id = p_faculty_id;

    -- Audit trail log
    INSERT INTO public.audit_logs (user_id, actor_email, action, table_name, record_id, details)
    VALUES (
        v_admin_id,
        v_admin_email,
        'FACULTY_ENROLLMENT_APPROVED',
        'profiles',
        p_faculty_id,
        jsonb_build_object(
            'approved_faculty_id', p_faculty_id,
            'reviewed_by_admin', v_admin_email,
            'timestamp', NOW()
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'faculty_id', p_faculty_id,
        'status', 'approved'
    );
END;
$$;

-- 7. RPC: Server-Enforced Admin Rejection of Faculty Enrollment
CREATE OR REPLACE FUNCTION public.reject_faculty_enrollment(
    p_faculty_id UUID,
    p_rejection_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_admin_role TEXT;
    v_admin_email TEXT;
    v_reason TEXT := COALESCE(TRIM(p_rejection_reason), 'Photograph does not meet facial biometric quality standards.');
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated request';
    END IF;

    -- Verify caller is an authorized administrator
    SELECT role::text, email INTO v_admin_role, v_admin_email
    FROM public.profiles
    WHERE id = v_admin_id;

    IF v_admin_role != 'admin' THEN
        RAISE EXCEPTION 'Unauthorized: Only institutional administrators can reject faculty enrollment requests.';
    END IF;

    -- Update verification record
    UPDATE public.faculty_face_verifications
    SET approval_status = 'rejected',
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        rejection_reason = v_reason
    WHERE faculty_id = p_faculty_id;

    -- Update profiles record: attendance remains strictly disabled
    UPDATE public.profiles
    SET is_approved = FALSE,
        approval_status = 'rejected',
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        rejection_reason = v_reason,
        updated_at = NOW()
    WHERE id = p_faculty_id;

    -- Audit trail log
    INSERT INTO public.audit_logs (user_id, actor_email, action, table_name, record_id, details)
    VALUES (
        v_admin_id,
        v_admin_email,
        'FACULTY_ENROLLMENT_REJECTED',
        'profiles',
        p_faculty_id,
        jsonb_build_object(
            'rejected_faculty_id', p_faculty_id,
            'rejection_reason', v_reason,
            'reviewed_by_admin', v_admin_email,
            'timestamp', NOW()
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'faculty_id', p_faculty_id,
        'status', 'rejected',
        'reason', v_reason
    );
END;
$$;
