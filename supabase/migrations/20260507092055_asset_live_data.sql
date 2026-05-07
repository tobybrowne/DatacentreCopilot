CREATE TABLE asset_live_data (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id uuid REFERENCES assets(id) ON DELETE CASCADE,
  data jsonb NOT NULL,
  alarm BOOLEAN NOT NULL DEFAULT FALSE,
  timestamp timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE asset_live_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow users to read live asset data for assets they have access to" ON asset_live_data
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM assets WHERE assets.id = asset_live_data.asset_id
  )
);