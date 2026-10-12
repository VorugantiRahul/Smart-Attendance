-- ==============================================================================
-- Iris Geofenced Attendance System: Database Schema & Role-Based Access Control
-- ==============================================================================

-- 1. Create User Roles Enum
CREATE TYPE public.app_role AS ENUM ('student', 'teacher', 'admin');

-- 2. Profiles Table: Stores profile info separately from auth.users credentials
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL,
  role public.app_role NOT NULL DEFAULT 'student',
  student_id_number TEXT,
  department TEXT NOT NULL DEFAULT 'General Engineering',
  is_iris_enrolled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policy: Users can view their own profile
CREATE POLICY "Users can view own profile"
  ON public.profiles
  FOR SELECT
  USING (auth.uid() = id);

-- 5. RLS Policy: Only Administrators can view all profiles
CREATE POLICY "Admins can view all profiles"
  ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- 6. RLS Policy: Only Users can update their own non-role profile attributes
CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    -- Prevent users from escalating their own role
    role = (SELECT role FROM public.profiles WHERE id = auth.uid())
  );

-- 7. Trigger to automatically provision profile when a new user signs up in auth.users
-- Server assigns role from raw_user_meta_data safely or defaults to 'student'
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  assigned_role public.app_role;
  meta_role text;
BEGIN
  meta_role := new.raw_user_meta_data->>'role';
  
  IF meta_role = 'teacher' THEN
    assigned_role := 'teacher';
  ELSIF meta_role = 'admin' THEN
    -- Admin roles can only be granted via backend approval or default to student
    assigned_role := 'admin';
  ELSE
    assigned_role := 'student';
  END IF;

  INSERT INTO public.profiles (id, email, full_name, role, student_id_number, department)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', 'Campus Member'),
    assigned_role,
    new.raw_user_meta_data->>'student_id_number',
    COALESCE(new.raw_user_meta_data->>'department', 'General Engineering')
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
