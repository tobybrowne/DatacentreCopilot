-- Logs subsystem
-- procedure_runs tracks each time a user executes a procedure.
-- logs capture per-step recordings; they can be standalone (no procedure_run) or attached to a run.
-- log_assets links a log entry to the assets that were relevant at that step.

CREATE TABLE procedure_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  procedure_id UUID NOT NULL REFERENCES procedures(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  started_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP -- null until the procedure is finished
);

-- RLS: users can select/insert procedure runs for procedures they have access to
ALTER TABLE procedure_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view procedure runs for procedures they have access to"
ON procedure_runs FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM procedures
    WHERE procedures.id = procedure_runs.procedure_id
  )
);
CREATE POLICY "Users can insert procedure runs for procedures they have access to"
ON procedure_runs FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM procedures
    WHERE procedures.id = procedure_runs.procedure_id
  )
);


-- logs can also be standalone, with no procedure_run or step association
CREATE TABLE logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  procedure_run_id UUID REFERENCES procedure_runs(id) ON DELETE CASCADE, -- nullable: standalone log
  step_id TEXT,                    -- references step.id in the procedure's JSONB steps array
  geometry_recording_path TEXT,    -- path to geometry/depth recording in Supabase storage
  camera_recording_path TEXT,      -- path to camera video recording in Supabase storage
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- RLS: users can select/insert logs for sites they have access to
ALTER TABLE logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view logs for sites they have access to"
ON logs FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = logs.site_id
  )
);
CREATE POLICY "Users can insert logs for sites they have access to"
ON logs FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = logs.site_id
  )
);


-- logs can be associated with many assets
CREATE TABLE log_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  log_id UUID NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
  asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE
);

-- RLS: users can select/insert log_assets for assets and logs they have access to
ALTER TABLE log_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view log_assets for assets and logs they have access to"
ON log_assets FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM logs
    WHERE logs.id = log_assets.log_id
  )
  AND EXISTS (
    SELECT 1
    FROM assets
    WHERE assets.id = log_assets.asset_id
  )
);
CREATE POLICY "Users can insert log_assets for assets and logs they have access to"
ON log_assets FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM logs
    WHERE logs.id = log_assets.log_id
  )
  AND EXISTS (
    SELECT 1
    FROM assets
    WHERE assets.id = log_assets.asset_id
  )
);
