-- buildings
DROP POLICY IF EXISTS "Users can view buildings for sites they belong to" ON buildings;
CREATE POLICY "Users can view buildings for sites they belong to"
ON buildings FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM sites
    WHERE sites.id = buildings.site_id
  )
);

-- procedures
DROP POLICY IF EXISTS "Users can view procedures for buildings they belong to" ON procedures;
CREATE POLICY "Users can view procedures for buildings they belong to"
ON procedures FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM buildings
    WHERE buildings.id = procedures.building_id
  )
);

-- spaces
DROP POLICY IF EXISTS "Users can view spaces for sites they belong to" ON spaces;
CREATE POLICY "Users can view spaces for sites they belong to"
ON spaces FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM sites
    WHERE sites.id = spaces.site_id
  )
);

-- anchors
DROP POLICY IF EXISTS "Users can view anchors for spaces they have access to" ON anchors;
CREATE POLICY "Users can view anchors for spaces they have access to"
ON anchors FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM spaces
    WHERE spaces.id = anchors.space_id
  )
);
