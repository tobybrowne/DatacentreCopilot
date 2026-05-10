-- Fix unqualified `users` reference in spaces_bucket INSERT policy.
-- In the storage schema context `users` does not resolve to public.users;
-- the UPDATE policy already uses the explicit prefix — align INSERT to match.
DROP POLICY IF EXISTS "spaces_bucket: insert" ON storage.objects;

CREATE POLICY "spaces_bucket: insert"
ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'spaces_bucket'
  AND EXISTS (
    SELECT 1 FROM public.users WHERE public.users.site_id IS NOT NULL
  )
);
