-- create users - wraps auth.users
CREATE TABLE users (
  -- id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  id UUID NOT NULL,
  contact_email text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  glb_position jsonb DEFAULT '{}',
  PRIMARY KEY (id)
);
ALTER TABLE users REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE users;

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

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

INSERT INTO users (id, contact_email) VALUES ('00000000-0000-0000-0000-000000000000', 'demo@entangl.ai');

CREATE TABLE procedures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  steps TEXT[] NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE spaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  blob_path TEXT NOT NULL, -- path to the binary space export file in Supabase storage
  glb_path TEXT, -- path to the glb export file in Supabase storages
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- create private bucket for storing space exports (.glbs and blobs)
INSERT INTO storage.buckets (id, name, public)
VALUES ('spaces_bucket', 'spaces_bucket', true);

CREATE TABLE anchors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- supabase only UUID
  name TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  ml2_id UUID DEFAULT NULL, -- ML2's UUID for this anchor, if available
  glb_position jsonb, -- {x, y, z} in the GLB/mesh coordinate frame
  is_reference boolean NOT NULL DEFAULT false, -- currently, all ML2 anchors are reference
  space_id UUID NOT NULL REFERENCES spaces(id) ON DELETE CASCADE
);

