-- Make spaces_bucket private
UPDATE storage.buckets SET public = false WHERE id = 'spaces_bucket';

-- RLS on navmeshes table: accessible if user can see the building referencing it
ALTER TABLE navmeshes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view navmeshes for buildings they have access to"
ON navmeshes FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM buildings
    WHERE buildings.navmesh_id = navmeshes.id
  )
);

-- RLS for spaces_bucket: allow access if path exists in a space or navmesh the user can see
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

CREATE POLICY "Authenticated users can upload space files"
ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'spaces_bucket'
  AND EXISTS (
    SELECT 1 FROM site_users
    WHERE site_users.user_id = (SELECT auth.uid())
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
