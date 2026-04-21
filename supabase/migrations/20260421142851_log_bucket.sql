-- create private bucket for storing log/audit related files
INSERT INTO storage.buckets (id, name, public)
VALUES ('log_bucket', 'log_bucket', false);

-- RLS for log_bucket: allow access if path exists in a log row the user can see
CREATE POLICY "Users can read log files they have access to"
ON storage.objects FOR SELECT USING (
  bucket_id = 'log_bucket'
  AND (
    EXISTS (
        SELECT 1 FROM logs
        WHERE logs.camera_recording_path = name
        OR logs.geometry_recording_path = name
    )
  )
);

CREATE POLICY "Authenticated users can upload log files"
ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'log_bucket'
  AND EXISTS (
    SELECT 1 FROM site_users
    WHERE site_users.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Users can delete log files they have access to"
ON storage.objects FOR DELETE USING (
  bucket_id = 'log_bucket'
  AND (
    EXISTS (
        SELECT 1 FROM logs
        WHERE logs.camera_recording_path = name
        OR logs.geometry_recording_path = name
    )
  )
);
