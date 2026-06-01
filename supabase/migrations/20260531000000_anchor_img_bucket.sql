-- Reference photos for anchors: captured on the ML2 when a reference anchor is
-- created in calibration mode, and shown on the desktop while mapping that anchor
-- to the mesh.

ALTER TABLE anchors ADD COLUMN IF NOT EXISTS img_path TEXT;

-- Private bucket for the anchor reference images
INSERT INTO storage.buckets (id, name, public)
VALUES ('anchor_img_bucket', 'anchor_img_bucket', false)
ON CONFLICT (id) DO NOTHING;

-- RLS for anchor_img_bucket: read/delete if the path is referenced by an anchor
-- row the user can see; upload allowed for any authenticated site user.
-- (auth.uid() -> users.site_id is the post-single-site access chain.)
DROP POLICY IF EXISTS "Users can read anchor images they have access to" ON storage.objects;
CREATE POLICY "Users can read anchor images they have access to"
ON storage.objects FOR SELECT USING (
  bucket_id = 'anchor_img_bucket'
  AND EXISTS (
    SELECT 1 FROM anchors
    WHERE anchors.img_path = name
  )
);

DROP POLICY IF EXISTS "Authenticated users can upload anchor images" ON storage.objects;
CREATE POLICY "Authenticated users can upload anchor images"
ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'anchor_img_bucket'
  AND EXISTS (
    SELECT 1 FROM users WHERE users.site_id IS NOT NULL
  )
);

DROP POLICY IF EXISTS "Users can delete anchor images they have access to" ON storage.objects;
CREATE POLICY "Users can delete anchor images they have access to"
ON storage.objects FOR DELETE USING (
  bucket_id = 'anchor_img_bucket'
  AND EXISTS (
    SELECT 1 FROM anchors
    WHERE anchors.img_path = name
  )
);
