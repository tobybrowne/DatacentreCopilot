-- Fix anchor_img_bucket read/delete policies.
--
-- The original policies used a bare `name` inside the subquery over `anchors`.
-- Since `anchors` has its own `name` column, that identifier bound to
-- `anchors.name` instead of `storage.objects.name`, making the condition
-- `anchors.img_path = anchors.name` (always false) - so signing/reading and
-- deleting anchor images was always denied. Qualify it as `objects.name`.

DROP POLICY IF EXISTS "Users can read anchor images they have access to" ON storage.objects;
CREATE POLICY "Users can read anchor images they have access to"
ON storage.objects FOR SELECT USING (
  bucket_id = 'anchor_img_bucket'
  AND EXISTS (
    SELECT 1 FROM anchors
    WHERE anchors.img_path = objects.name
  )
);

DROP POLICY IF EXISTS "Users can delete anchor images they have access to" ON storage.objects;
CREATE POLICY "Users can delete anchor images they have access to"
ON storage.objects FOR DELETE USING (
  bucket_id = 'anchor_img_bucket'
  AND EXISTS (
    SELECT 1 FROM anchors
    WHERE anchors.img_path = objects.name
  )
);
