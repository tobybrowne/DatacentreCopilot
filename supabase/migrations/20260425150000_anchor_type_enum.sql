CREATE TYPE anchor_type_enum AS ENUM ('reference', 'content', 'temp', 'note', 'asset');

ALTER TABLE anchors DROP CONSTRAINT IF EXISTS anchors_anchor_type_check;

ALTER TABLE anchors ALTER COLUMN anchor_type DROP DEFAULT;

ALTER TABLE anchors
  ALTER COLUMN anchor_type TYPE anchor_type_enum
  USING anchor_type::anchor_type_enum;

ALTER TABLE anchors ALTER COLUMN anchor_type SET DEFAULT 'content';
