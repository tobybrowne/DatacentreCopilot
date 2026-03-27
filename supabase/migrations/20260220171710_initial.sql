-- create users - wraps auth.users
CREATE TABLE users (
    id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
    contact_email text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- auto-create users when auth.users are created
CREATE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.users (id, contact_email)
  VALUES (NEW.id, NEW.email);
  RETURN NEW;
END;
$$;

-- create procedures table
CREATE TABLE procedures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    steps TEXT[] NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- create anchors table
-- Add mesh-space position for desktop-placed anchors.
-- mesh_position is {x, y, z} in the GLB/mesh coordinate frame.
-- source distinguishes headset-placed vs desktop-placed anchors.
CREATE TABLE anchors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- supabase only UUID
    name TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    ml2_id UUID DEFAULT NULL, -- ML2's UUID for this anchor, if available
    glb_position jsonb, -- {x, y, z} in the GLB/mesh coordinate frame
    is_reference boolean NOT NULL DEFAULT false -- currently, all ML2 anchors are reference
);
