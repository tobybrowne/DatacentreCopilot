-- Replace building_spaces junction table with a direct nullable FK on spaces

ALTER TABLE spaces
  ADD COLUMN building_id UUID REFERENCES buildings(id) ON DELETE SET NULL,
  ADD COLUMN building_index INT,
  ADD COLUMN offset_transformation JSONB;

-- Migrate existing data (take first match per space if duplicates exist)
UPDATE spaces
  SET
    building_id            = bs.building_id,
    building_index         = bs.index,
    offset_transformation  = bs.offset_transformation
  FROM (
    SELECT DISTINCT ON (space_id) space_id, building_id, index, offset_transformation
    FROM building_spaces
    ORDER BY space_id, index
  ) bs
  WHERE spaces.id = bs.space_id;

-- Drop building_spaces policies then the table
DROP POLICY IF EXISTS "Users can view building_spaces for buildings they belong to" ON building_spaces;
DROP POLICY IF EXISTS "Users can insert building_spaces for their buildings" ON building_spaces;
DROP POLICY IF EXISTS "Users can delete building_spaces for their buildings" ON building_spaces;
DROP TABLE building_spaces;
