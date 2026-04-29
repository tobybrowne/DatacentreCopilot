-- Spaces subsystem
-- A site has many buildings. A building has many spaces.
-- Spaces are physically scanned rooms; buildings stitch spaces together via offset_transformation.
-- Navmeshes are generated per-building for pathfinding.

CREATE TABLE navmeshes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  navmesh_path TEXT NOT NULL, -- path to the navmesh file in Supabase storage
  build_settings JSONB NOT NULL, -- the settings used to build this navmesh
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);


CREATE TABLE buildings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  draft BOOLEAN NOT NULL DEFAULT true, -- true while spaces are still being stitched together
  navmesh_id UUID REFERENCES navmeshes(id) ON DELETE SET NULL,
  site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS: navmeshes accessible if user can see the building referencing it
ALTER TABLE navmeshes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view navmeshes for buildings they have access to"
ON navmeshes FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM buildings
    WHERE buildings.navmesh_id = navmeshes.id
  )
);

-- RLS: users can see/modify buildings for sites they belong to
ALTER TABLE buildings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view buildings for sites they belong to"
ON buildings FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = buildings.site_id
  )
);
CREATE POLICY "Users can insert buildings for their sites"
ON buildings FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = buildings.site_id
  )
);
CREATE POLICY "Users can delete buildings for their sites"
ON buildings FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = buildings.site_id
  )
);


-- Storage bucket: spaces_bucket (private) — stores .blob and .glb exports
INSERT INTO storage.buckets (id, name, public) VALUES ('spaces_bucket', 'spaces_bucket', false);

CREATE TABLE spaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  blob_path TEXT NOT NULL, -- path to the binary space export (.blob) in Supabase storage
  glb_path TEXT,           -- path to the GLB mesh export in Supabase storage
  site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  building_id UUID REFERENCES buildings(id) ON DELETE SET NULL, -- null until assigned to a building
  building_index INT,          -- ordering of this space within its building
  offset_transformation JSONB, -- rigid transform {position, rotation} relative to space 0 in the building
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS: users can see/modify spaces for sites they belong to
ALTER TABLE spaces ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view spaces for sites they belong to"
ON spaces FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = spaces.site_id
  )
);
CREATE POLICY "Users can insert spaces for their sites"
ON spaces FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = spaces.site_id
  )
);
CREATE POLICY "Users can delete spaces for their sites"
ON spaces FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = spaces.site_id
  )
);

-- Storage RLS: spaces_bucket access gated on path existence in accessible spaces/navmeshes
CREATE POLICY "Users can read space files they have access to"
ON storage.objects FOR SELECT USING (
  bucket_id = 'spaces_bucket'
  AND (
    EXISTS (
      SELECT 1 FROM spaces
      WHERE spaces.blob_path = objects.name
         OR spaces.glb_path = objects.name
    )
    OR EXISTS (
      SELECT 1 FROM navmeshes
      WHERE navmeshes.navmesh_path = objects.name
    )
  )
);

CREATE POLICY "spaces_bucket: insert"
ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'spaces_bucket'
  AND EXISTS (
    SELECT 1 FROM users WHERE users.site_id IS NOT NULL
  )
);

CREATE POLICY "Users can delete space files they have access to"
ON storage.objects FOR DELETE USING (
  bucket_id = 'spaces_bucket'
  AND (
    EXISTS (
      SELECT 1 FROM spaces
      WHERE spaces.blob_path = objects.name
         OR spaces.glb_path = objects.name
    )
    OR EXISTS (
      SELECT 1 FROM navmeshes
      WHERE navmeshes.navmesh_path = objects.name
    )
  )
);
