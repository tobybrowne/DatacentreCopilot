-- Anchors subsystem
-- Anchors are spatial markers placed within a space.
-- anchor_type determines the role: reference (ML2 world-lock), content (asset/POI), note, temp.
-- Notes are linked to anchors via notes.anchor_id (many notes can belong to one anchor).

CREATE TABLE anchors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  anchor_type TEXT NOT NULL DEFAULT 'content'
    CHECK (anchor_type IN ('reference', 'content', 'temp', 'note')),
  ml2_id UUID DEFAULT NULL,    -- ML2's UUID for this anchor (present on reference anchors)
  glb_position JSONB,          -- {x, y, z} in the GLB/mesh coordinate frame
  space_id UUID NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS: users can see/modify anchors for spaces they have access to
ALTER TABLE anchors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view anchors for spaces they have access to"
ON anchors FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM spaces
    WHERE spaces.id = anchors.space_id
  )
);
CREATE POLICY "Users can insert anchors for their spaces"
ON anchors FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM spaces
    WHERE spaces.id = anchors.space_id
  )
);
CREATE POLICY "Users can delete anchors for their spaces"
ON anchors FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM spaces
    WHERE spaces.id = anchors.space_id
  )
);


CREATE TABLE notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  text TEXT NOT NULL,
  anchor_id UUID REFERENCES anchors(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: users can see/modify notes for anchors they have access to
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view notes for anchors they have access to"
ON notes FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM anchors
    WHERE anchors.id = notes.anchor_id
  )
);
CREATE POLICY "Users can insert notes for their anchors"
ON notes FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM anchors
    WHERE anchors.id = notes.anchor_id
  )
);
CREATE POLICY "Users can delete notes for their anchors"
ON notes FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM anchors
    WHERE anchors.id = notes.anchor_id
  )
);
