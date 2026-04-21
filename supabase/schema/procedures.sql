-- Procedures subsystem
-- A procedure is an ordered list of steps stored as JSONB[].
-- Each step: { "id": "<uuid>", "text": "...", "timer": { "duration": 300, "target_uuid": "<step-id>" } }
-- timer is optional; target_uuid is the step id at which the countdown should be dismissed.
-- gesture_recordings store motion-capture data tied to a specific step.

CREATE TABLE procedures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  steps JSONB[] NOT NULL DEFAULT '{}', -- ordered array of step objects
  building_id UUID REFERENCES buildings(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS: users can see/modify procedures for buildings they have access to
ALTER TABLE procedures ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view procedures for buildings they belong to"
ON procedures FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE buildings.id = procedures.building_id
  )
);
CREATE POLICY "Users can insert procedures for their buildings"
ON procedures FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE buildings.id = procedures.building_id
  )
);
CREATE POLICY "Users can delete procedures for their buildings"
ON procedures FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE buildings.id = procedures.building_id
  )
);


-- Storage bucket: gesture_recordings_bucket (public) — stores gesture recording JSON files
INSERT INTO storage.buckets (id, name, public) VALUES ('gesture_recordings_bucket', 'gesture_recordings_bucket', true);

CREATE TABLE gesture_recordings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  procedure_id UUID NOT NULL REFERENCES procedures(id) ON DELETE CASCADE,
  step_uuid UUID NOT NULL,       -- references step.id in the procedure's JSONB steps array
  recording_path TEXT NOT NULL,  -- path to the gesture recording (.json) in Supabase storage
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
