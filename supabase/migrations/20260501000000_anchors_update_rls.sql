-- Add missing UPDATE policies across all tables.
-- RLS was enabled with SELECT/INSERT/DELETE but UPDATE was never added,
-- causing silent no-ops on all update operations.

CREATE POLICY "Users can update anchors for their spaces"
ON anchors FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM spaces WHERE spaces.id = anchors.space_id
  )
);

CREATE POLICY "Users can update notes for their anchors"
ON notes FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM anchors WHERE anchors.id = notes.anchor_id
  )
);

CREATE POLICY "Users can update buildings for their sites"
ON buildings FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM sites WHERE sites.id = buildings.site_id
  )
);

CREATE POLICY "Users can update spaces for their sites"
ON spaces FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM sites WHERE sites.id = spaces.site_id
  )
);

CREATE POLICY "Users can update procedures for their buildings"
ON procedures FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM buildings WHERE buildings.id = procedures.building_id
  )
);

CREATE POLICY "Users can update their own user record"
ON users FOR UPDATE USING (auth.uid() = id);
