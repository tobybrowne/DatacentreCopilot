
CREATE TABLE site_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE
);

ALTER TABLE buildings ADD COLUMN site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE;

ALTER TABLE spaces ADD COLUMN site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE;

-- RLS: users can see their own rows in users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own user record" ON users
    FOR SELECT USING (auth.uid() = id);

-- RLS: users can see their own rows in site_users
ALTER TABLE site_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own site user record" ON site_users
    FOR SELECT USING (auth.uid() = user_id);

-- RLS: users can see their own rows in sites
ALTER TABLE sites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view sites they belong to"
ON sites FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM site_users
    WHERE user_id = (SELECT auth.uid())
      AND site_id = id
  )
);

-- RLS: users can see buildings for sites they belong to
-- this means every user on a site can see all buildings, we may want to filter that later
ALTER TABLE buildings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view buildings for sites they belong to"
ON buildings FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE site_id = buildings.site_id
  )
);

-- RLS: users can see procedures for buildings they belong to
ALTER TABLE procedures ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view procedures for buildings they belong to"
ON procedures FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE building_id = procedures.building_id
  )
);

-- RLS: users can see spaces for sites they belong to
ALTER TABLE spaces ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view spaces for sites they belong to"
ON spaces FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE site_id = spaces.site_id
  )
);

-- RLS: users can see building_spaces mappings for buildings they belong to
ALTER TABLE building_spaces ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view building_spaces for buildings they belong to"
ON building_spaces FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE building_id = building_spaces.building_id
  )
);

-- RLS: users can see anchors for spaces they have access to
ALTER TABLE anchors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view anchors for spaces they have access to"
ON anchors FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM spaces
    WHERE space_id = anchors.space_id
  )
);

-- RLS: users can see notes attached to anchors they have access to
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view notes for anchors they have access to"
ON notes FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM anchors
    WHERE anchor_id = notes.anchor_id
  )
);