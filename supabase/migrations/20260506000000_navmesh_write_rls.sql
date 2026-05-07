-- Allow authenticated users (with a site) to insert navmesh rows
CREATE POLICY "Site members can insert navmeshes"
ON navmeshes FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = (SELECT auth.uid())
      AND users.site_id IS NOT NULL
  )
);

-- Allow users to update navmesh rows for buildings on their site
CREATE POLICY "Site members can update navmeshes"
ON navmeshes FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM buildings
    JOIN users ON users.site_id = buildings.site_id
    WHERE buildings.navmesh_id = navmeshes.id
      AND users.id = (SELECT auth.uid())
  )
);

-- Allow users to update buildings on their site
CREATE POLICY "Site members can update buildings"
ON buildings FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.site_id = buildings.site_id
      AND users.id = (SELECT auth.uid())
  )
);
