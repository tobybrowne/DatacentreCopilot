-- initialise the procedures table
-- steps is JSONB[]: each element is {"type": "instruction"|"goto", "text": "...", "anchor_id": "<uuid>"}
-- anchor_id is only required for goto steps; use a real anchor UUID in production.
INSERT INTO procedures (title, steps) VALUES
(
  'Procedure 1',
  ARRAY[
    '{"type":"instruction","text":"Pick up the instrument"}'::jsonb,
    '{"type":"instruction","text":"Position over the target area"}'::jsonb,
    '{"type":"goto","text":"Proceed to the storage cabinet","anchor_id":"00000000-0000-0000-0000-000000000001"}'::jsonb
  ]
),
(
  'Procedure 2',
  ARRAY[
    '{"type":"instruction","text":"Step 1 for Procedure 2"}'::jsonb,
    '{"type":"instruction","text":"Step 2 for Procedure 2"}'::jsonb,
    '{"type":"instruction","text":"Step 3 for Procedure 2"}'::jsonb
  ]
),
(
  'Procedure 3',
  ARRAY[
    '{"type":"instruction","text":"Step 1 for Procedure 3"}'::jsonb,
    '{"type":"instruction","text":"Step 2 for Procedure 3"}'::jsonb,
    '{"type":"instruction","text":"Step 3 for Procedure 3"}'::jsonb
  ]
);
