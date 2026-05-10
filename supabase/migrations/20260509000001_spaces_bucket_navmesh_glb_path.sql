DROP POLICY IF EXISTS "Users can read space files they have access to" ON storage.objects;
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
         OR navmeshes.glb_path = objects.name
    )
  )
);

DROP POLICY IF EXISTS "Users can delete space files they have access to" ON storage.objects;
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
         OR navmeshes.glb_path = objects.name
    )
  )
);
