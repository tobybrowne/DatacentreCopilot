-- Allow 'note' as an anchor type for sticky note anchors.
ALTER TABLE anchors
  DROP CONSTRAINT IF EXISTS anchors_anchor_type_check;

ALTER TABLE anchors
  ADD CONSTRAINT anchors_anchor_type_check
    CHECK (anchor_type IN ('reference', 'content', 'temp', 'note'));

-- Sticky notes: user-placed text notes attached to a spatial anchor.
CREATE TABLE notes (
  id         UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  text       TEXT        NOT NULL,
  anchor_id  UUID        REFERENCES anchors(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public access" ON notes FOR ALL USING (true);
