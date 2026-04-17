-- Migrate procedures.steps from TEXT[] to JSONB[]
-- Each plain-text step becomes {"type": "instruction", "text": "<original text>"}
-- New step types (e.g. "goto") can now be added by including additional keys.
--
-- ALTER COLUMN ... USING does not allow subqueries (SQLSTATE 0A000), so we
-- use the add-column / UPDATE / swap pattern instead.

ALTER TABLE procedures ADD COLUMN steps_new JSONB[];

UPDATE procedures
SET steps_new = (
  SELECT array_agg(jsonb_build_object('type', 'instruction', 'text', s))
  FROM unnest(steps) s
);

ALTER TABLE procedures DROP COLUMN steps;
ALTER TABLE procedures RENAME COLUMN steps_new TO steps;
ALTER TABLE procedures ALTER COLUMN steps SET NOT NULL;
