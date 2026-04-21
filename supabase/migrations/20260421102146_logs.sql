CREATE TABLE procedure_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  procedure_id UUID NOT NULL REFERENCES procedures(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  started_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
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

-- a procedure run can have many logs associated with it, usually one per step
-- logs can also be standalone, with no procedure_run or step association
CREATE TABLE logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- both nullable
    procedure_run_id UUID REFERENCES procedure_runs(id) ON DELETE CASCADE,
    step_id TEXT,

    geometry_recording_path TEXT,
    camera_recording_path TEXT,

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
