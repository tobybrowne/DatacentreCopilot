-- Extend log_bucket read/delete policies to cover the ogv video path column.
DROP POLICY IF EXISTS "Users can read log files they have access to" ON storage.objects;
CREATE POLICY "Users can read log files they have access to"
ON storage.objects FOR SELECT USING (
  bucket_id = 'log_bucket'
  AND (
    EXISTS (
      SELECT 1 FROM logs
      WHERE logs.camera_recording_path = name
      OR logs.geometry_recording_path = name
      OR logs.camera_recording_path_ogv = name
    )
  )
);

DROP POLICY IF EXISTS "Users can delete log files they have access to" ON storage.objects;
CREATE POLICY "Users can delete log files they have access to"
ON storage.objects FOR DELETE USING (
  bucket_id = 'log_bucket'
  AND (
    EXISTS (
      SELECT 1 FROM logs
      WHERE logs.camera_recording_path = name
      OR logs.geometry_recording_path = name
      OR logs.camera_recording_path_ogv = name
    )
  )
);
