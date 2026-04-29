-- Replace many-to-many site_users with a single site_id on users.
-- RLS chain: auth.uid() → users.site_id → sites → buildings/spaces → anchors → notes
-- Only the sites SELECT policy needs updating; all downstream tables are unchanged.

-- Drop policies that reference site_users before dropping the table
DROP POLICY IF EXISTS "Users can view sites they belong to" ON sites;
DROP POLICY IF EXISTS "Users can view their own site user record" ON site_users;
DROP POLICY IF EXISTS "Authenticated users can upload space files" ON storage.objects;
DROP POLICY IF EXISTS "spaces_bucket: insert" ON storage.objects;

DROP TABLE IF EXISTS site_users;

ALTER TABLE users ADD COLUMN site_id UUID REFERENCES sites(id) ON DELETE SET NULL;

CREATE POLICY "Users can view sites they belong to"
ON sites FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM users WHERE users.site_id = sites.id
  )
);

CREATE POLICY "spaces_bucket: insert"
ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'spaces_bucket'
  AND EXISTS (
    SELECT 1 FROM users WHERE users.site_id IS NOT NULL
  )
);
