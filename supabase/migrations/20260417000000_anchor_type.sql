-- Replace is_reference boolean with an anchor_type enum column.
-- Types: 'reference' (Kabsch ref point), 'content' (placed content), 'temp' (transient routing anchor)
ALTER TABLE anchors
  ADD COLUMN anchor_type TEXT NOT NULL DEFAULT 'content'
    CHECK (anchor_type IN ('reference', 'content', 'temp'));

UPDATE anchors SET anchor_type = 'reference' WHERE is_reference = true;

ALTER TABLE anchors DROP COLUMN is_reference;
