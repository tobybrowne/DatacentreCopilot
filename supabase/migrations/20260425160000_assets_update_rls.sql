CREATE POLICY "Users can update assets for buildings they have access to"
ON assets FOR UPDATE USING (
  EXISTS (SELECT 1 FROM buildings WHERE id = assets.building_id)
) WITH CHECK (
  EXISTS (SELECT 1 FROM buildings WHERE id = assets.building_id)
);
