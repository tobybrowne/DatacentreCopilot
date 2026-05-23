-- Extend navmesh SELECT policy to cover floorplan_id references
DROP POLICY IF EXISTS "Users can view navmeshes for buildings they have access to" ON navmeshes;
CREATE POLICY "Users can view navmeshes for buildings they have access to"
ON navmeshes FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM buildings
    WHERE buildings.navmesh_id = navmeshes.id
       OR buildings.floorplan_id = navmeshes.id
  )
);

-- Extend navmesh UPDATE policy to cover floorplan_id references
DROP POLICY IF EXISTS "Site members can update navmeshes" ON navmeshes;
CREATE POLICY "Site members can update navmeshes"
ON navmeshes FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM buildings
    JOIN users ON users.site_id = buildings.site_id
    WHERE (buildings.navmesh_id = navmeshes.id OR buildings.floorplan_id = navmeshes.id)
      AND users.id = (SELECT auth.uid())
  )
);
