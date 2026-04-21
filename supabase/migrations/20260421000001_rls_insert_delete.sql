-- INSERT and DELETE policies matching existing SELECT permissions
-- All column references are fully qualified to avoid ambiguous resolution
-- sites and site_users are managed by service role only (no user insert/delete)

-- users: own record only
CREATE POLICY "Users can insert their own user record" ON users
    FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can delete their own user record" ON users
    FOR DELETE USING (auth.uid() = id);

-- buildings: must have access to the target site
CREATE POLICY "Users can insert buildings for their sites" ON buildings
    FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM sites
        WHERE sites.id = buildings.site_id
      )
    );
CREATE POLICY "Users can delete buildings for their sites" ON buildings
    FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM sites
        WHERE sites.id = buildings.site_id
      )
    );

-- procedures: must have access to the target building
CREATE POLICY "Users can insert procedures for their buildings" ON procedures
    FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM buildings
        WHERE buildings.id = procedures.building_id
      )
    );
CREATE POLICY "Users can delete procedures for their buildings" ON procedures
    FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM buildings
        WHERE buildings.id = procedures.building_id
      )
    );

-- spaces: must have access to the target site
CREATE POLICY "Users can insert spaces for their sites" ON spaces
    FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM sites
        WHERE sites.id = spaces.site_id
      )
    );
CREATE POLICY "Users can delete spaces for their sites" ON spaces
    FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM sites
        WHERE sites.id = spaces.site_id
      )
    );

-- building_spaces: must have access to the target building
CREATE POLICY "Users can insert building_spaces for their buildings" ON building_spaces
    FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM buildings
        WHERE buildings.id = building_spaces.building_id
      )
    );
CREATE POLICY "Users can delete building_spaces for their buildings" ON building_spaces
    FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM buildings
        WHERE buildings.id = building_spaces.building_id
      )
    );

-- anchors: must have access to the target space
CREATE POLICY "Users can insert anchors for their spaces" ON anchors
    FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM spaces
        WHERE spaces.id = anchors.space_id
      )
    );
CREATE POLICY "Users can delete anchors for their spaces" ON anchors
    FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM spaces
        WHERE spaces.id = anchors.space_id
      )
    );

-- notes: must have access to the target anchor
CREATE POLICY "Users can insert notes for their anchors" ON notes
    FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM anchors
        WHERE anchors.id = notes.anchor_id
      )
    );
CREATE POLICY "Users can delete notes for their anchors" ON notes
    FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM anchors
        WHERE anchors.id = notes.anchor_id
      )
    );
