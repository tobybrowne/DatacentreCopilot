-- Allow authenticated users to overwrite existing files in spaces_bucket (needed for upsert)
CREATE POLICY "spaces_bucket: update"
ON storage.objects FOR UPDATE USING (
  bucket_id = 'spaces_bucket'
  AND EXISTS (
    SELECT 1 FROM public.users WHERE users.site_id IS NOT NULL
  )
);
