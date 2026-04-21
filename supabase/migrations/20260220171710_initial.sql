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

CREATE TABLE navmeshes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  navmesh_path TEXT NOT NULL, -- path to the navmesh file in supabase storage
  build_settings jsonb NOT NULL, -- the settings used to build this navmesh
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE buildings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  draft boolean NOT NULL DEFAULT true, -- whether this building is still being stitched
  navmesh_id UUID REFERENCES navmeshes(id) ON DELETE CASCADE -- path to the navmesh file for this space in supabase storage
);

CREATE TABLE building_spaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  space_id UUID NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
  offset_transformation jsonb, -- the transformation between this space and space 0
  index int NOT NULL, -- the index of this space within the building, used for ordering
);

-- recordings of gesturs to accompany certain steps 
CREATE TABLE gesture_recordings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  procedure_id UUID NOT NULL REFERENCES procedures(id) ON DELETE CASCADE,
  step_uuid UUID NOT NULL, -- the step this gesture recording corresponds to
  recording_path TEXT NOT NULL, -- path to the gesture recording file in Supabase storage (.json)
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  start_anchor_id UUID NOT NULL REFERENCES anchors(id) ON DELETE CASCADE,
  end_anchor_id UUID NOT NULL REFERENCES anchors(id) ON DELETE CASCADE,
  waypoints jsonb NOT NULL -- the actual route data (list of waypoints - in building space coords)
);

-- create private bucket for storing gesture recordings
INSERT INTO storage.buckets (id, name, public)
VALUES ('gesture_recordings_bucket', 'gesture_recordings_bucket', true);